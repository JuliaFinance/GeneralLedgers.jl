"""
Ledgers

This package provides support for general financial ledgers

See README.md for the full documentation

Copyright 2019-2020, Eric Forgy, Scott P. Jones and other contributors

Licensed under MIT License, see LICENSE.md
"""
module Ledgers

using UUIDs, StructArrays, AbstractTrees
using Instruments, Assets
import Instruments: instrument, symbol, amount, name, currency

export Credit, Debit, Account, Ledger, Entry, AccountId, AccountInfo
export id, balance, credit!, debit!, post!, instrument, symbol, amount, name, currency

struct AccountId{T}
    value::T
end

Base.show(io::IO, id::AccountId) = print(io, id.value)

mutable struct Account{P<:Position,I<:AccountId}
    id::I
    balance::P
end
Account(balance::Position) = Account(AccountId(uuid4()), balance)

# Identity function (to make code more generic)
account(v::Account) = v

id(account::Account) = account.id
balance(account::Account) = account.balance

instrument(::Account{P}) where {P<:Position} = instrument(P)
symbol(::Account{P}) where {P<:Position} = symbol(P)
currency(::Account{P}) where {P<:Position} = currency(P)

amount(amt::Account) = amount(amt.balance)

debit!(account::Account, amt::Position) = (account.balance += amt)
credit!(account::Account, amt::Position) = (account.balance -= amt)

Base.show(io::IO, account::Account) = print(io, "$(string(id(account))): $(balance(account)).")

struct Entry{D,C}
    debit::D
    credit::C
end

Base.show(io::IO, e::Entry{<:Account,<:Account}) =
    print(io, "Entry:\n", "  Debit: $(e.debit)\n", "  Credit: $(e.credit)")

abstract type AccountType end
struct Credit <: AccountType end
struct Debit <: AccountType end

Base.show(io::IO, ::Type{Debit}) = print(io, "Debit")
Base.show(io::IO, ::Type{Credit}) = print(io, "Credit")

# SPJ: this does not maintain the distinction we'd talked about, of keeping
# all debit accounts and all credit accounts in with separate types.
# This will end up doing a lot of processing at run-time, and will be relatively
# rather slow compared to what we had discussed.

struct AccountInfo{T<:AccountType}
    account::Account
    name::String
    parent::Union{Nothing,AccountInfo}
    subaccounts::Vector{AccountInfo}

    function AccountInfo(::Type{T}, account, name, parent=nothing) where {T<:AccountType}
        ag = new{T}(account, name, parent, Vector{AccountInfo}())
        (parent === nothing) || push!(parent.subaccounts, ag)
        return ag
    end
end

account(info::AccountInfo) = info.account
name(info::AccountInfo) = info.name
parent(info::AccountInfo) = info.parent
subaccounts(info::AccountInfo) = info.subaccounts

id(info::AccountInfo) = id(account(info))
balance(info::AccountInfo{Debit}) = 
    isempty(subaccounts(info)) ? balance(account(info)) : 
    balance(account(info)) + sum(map(info->balance(account(info)), subaccounts(info)))
balance(info::AccountInfo{Credit}) = 
    isempty(subaccounts(info)) ? -balance(account(info)) :
    -balance(account(info)) - sum(map(info->balance(account(info)), subaccounts(info)))

function post!(entry::Entry, amt::Position)
    debit!(account(entry.debit), amt)
    credit!(account(entry.credit), amt)
    entry
end

AbstractTrees.children(info::AccountInfo) =
    isempty(subaccounts(info)) ? Vector{AccountInfo}() : subaccounts(info)
AbstractTrees.printnode(io::IO,info::AccountInfo) =
    print(io, "$(name(info)) ($(id(info))): $(balance(info))")

Base.show(io::IO,info::AccountInfo) =
    isempty(subaccounts(info)) ? printnode(io, info) : print_tree(io, info)

function Base.show(io::IO, e::Entry)
    print(io,
          "Entry:\n",
          "  Debit: $(name(e.debit)) ($(id(e.debit))): $(balance(e.debit))\n",
          "  Credit: $(name(e.credit)) ($(id(e.credit))): $(balance(e.credit))\n")
end

struct Ledger{P<:Position,I<:AccountId}
    indexes::Dict{I,Int}
    accounts::StructArray{Account{P,I}}

    function Ledger(accounts::Vector{Account{P,I}}) where {P<:Position,I<:AccountId}
        indexes = Dict{I,Int}()
        for (index, account) in enumerate(accounts)
            indexes[id(account)] = index
        end
        new{P,I}(indexes, StructArray(accounts))
    end
end

Base.getindex(ledger::Ledger, ix) = ledger.accounts[ix]

Base.getindex(ledger::Ledger, id::AccountId) =
    ledger.accounts[ledger.indexes[id]]
Base.getindex(ledger::Ledger, array::AbstractVector{<:AccountId}) =
    ledger.accounts[broadcast(id->ledger.indexes[id], array)]

function add_account!(ledger::Ledger, account::Account)
    push!(ledger.accounts, account)
    ledger.indexes[id(account)] = length(ledger.accounts)
end

# const chartofaccounts = Dict{String,AccountGroup{<:Cash}}()

# function getledger(a::AccountGroup)
#     while !isequal(a,a.parent)
#         a = a.parent
#     end
#     return a
# end

# function add(a::AccountGroup)
#         haskey(chartofaccounts,a.code) && error("AccountGroup with code $(a.code) already exists.")
#         chartofaccounts[a.code] = a
#         return a
# end

# iscontra(a::AccountGroup) = !isequal(a,a.parent) && !isequal(a.parent,getledger(a)) && !isequal(a.parent.isdebit,a.isdebit)

# function loadchart(ledgername,ledgercode,csvfile)
#     data, headers = readdlm(csvfile,',',String,header=true)
#     nrow,ncol = size(data)

#     ledger = add(AccountGroup(ledgername,ledgercode))
#     for i = 1:nrow
#         row = data[i,:]
#         code = row[1]
#         name = row[2]
#         parent = chartofaccounts[row[3]]
#         isdebit = isequal(row[4],"Debit")
#         add(AccountGroup(parent,name,code,isdebit))
#     end
#     return ledger
# end

# function trim(a::AccountGroup,newparent::AccountGroup=AccountGroup(a.parent.name,a.parent.code))
#     newaccount = isequal(a,a.parent) ? newparent : AccountGroup(newparent,a.name,a.code,a.isdebit,a.balance)
#     for subaccount in a.subaccounts
#         balance(subaccount).amount > 0. && trim(subaccount,newaccount)
#     end
#     return newaccount
# end

end # module Ledgers
