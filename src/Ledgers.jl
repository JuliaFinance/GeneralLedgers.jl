"""
Ledgers

This package provides support for general financial ledgers

See README.md for the full documentation

Copyright 2019-2020, Eric Forgy, Scott P. Jones and other contributors

Licensed under MIT License, see LICENSE.md
"""
module Ledgers

using DelimitedFiles, UUIDs, StructArrays, AbstractTrees
using Instruments, Assets
import Instruments: instrument, symbol, amount, name, currency

export Credit, Debit, Account, Ledger, Entry, AccountId, AccountInfo
export id, balance, credit!, debit!, post!, instrument, symbol, amount, name, currency

struct AccountId{ID}
    value::ID
end

Base.show(io::IO, id::AccountId) = print(io, id.value)

mutable struct Account{B<:Position,ID<:AccountId}
    id::ID
    balance::B
end
Account(balance::Position) = Account(AccountId(uuid4()), balance)

id(account::Account) = account.id
balance(account::Account) = account.balance

instrument(::Account{B}) where {B<:Position} = instrument(B)
symbol(::Account{B}) where {B<:Position} = symbol(B)
currency(::Account{B}) where {B<:Position} = currency(B)

amount(a::Account) = amount(a.balance)

debit!(account::Account, amt::Position) = (account.balance += amt)
credit!(account::Account, amt::Position) = (account.balance -= amt)

Base.show(io::IO, account::Account) = print(io, "$(string(id(account))): $(balance(account)).")

struct Entry{D,C}
    debit::D
    credit::C
end

Base.show(io::IO, e::Entry{D,C}) where {D<:Account,C<:Account} =
    print(io, "Entry:\n", "  Debit: $(e.debit)\n", "  Credit: $(e.credit)")
#Base.show(io::IO,::MIME"text/plain",e::Entry{D,C}) where {D<:Account,C<:Account} =
#    print(io, "Entry:\n", "  Debit: $(e.debit)\n", "  Credit: $(e.credit)")

function post!(entry::Entry{D,C}, amt::Position) where {D<:Account,C<:Account}
    debit!(entry.debit, amt)
    credit!(entry.credit, amt)
    entry
end

abstract type AccountType end
struct Credit <: AccountType end
struct Debit <: AccountType end

Base.show(io::IO, ::Type{Debit}) = print(io, "Debit")
Base.show(io::IO, ::Type{Credit}) = print(io, "Credit")

struct AccountInfo{AT<:AccountType}
    account::Account
    name::String
    parent::Union{Nothing,AccountInfo}
    subaccounts::Vector{AccountInfo}

    function AccountInfo(::Type{AT}, account, name, parent=nothing) where {AT<:AccountType}
        ag = new{AT}(account, name, parent, Vector{AccountInfo}())
        isnothing(parent) || push!(parent.subaccounts, ag)
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

function post!(entry::Entry{D,C}, amt::Position) where {D<:AccountInfo,C<:AccountInfo}
    debit!(entry.debit.account, amt)
    credit!(entry.credit.account, amt)
    entry
end

AbstractTrees.children(info::AccountInfo) =
    isempty(subaccounts(info)) ? Vector{AccountInfo}() : subaccounts(info)
AbstractTrees.printnode(io::IO,info::AccountInfo{AT}) where {AT<:AccountType} =
    print(io, "$(name(info)) ($(id(info))): $(balance(info))")
Base.show(io::IO,info::AccountInfo) =
    isempty(subaccounts(info)) ? printnode(io, info) : print_tree(io, info)
#Base.show(io::IO,::MIME"text/plain",info::AccountInfo) =
#    isempty(subaccounts(info)) ? printnode(io, info) : print_tree(io, info)

Base.show(io::IO,e::Entry{D,C}) where {D<:AccountInfo,C<:AccountInfo} =
    print(io,
    "Entry:\n",
    "  Debit: $(name(e.debit)) ($(id(e.debit))): $(balance(e.debit))\n",
          "  Credit: $(name(e.credit)) ($(id(e.credit))): $(balance(e.credit))\n")
#=
Base.show(io::IO,::MIME"text/plain",e::Entry{D,C}) where {D<:AccountInfo,C<:AccountInfo} =
    print(io,
    "Entry:\n",
    "  Debit: $(name(e.debit)) ($(id(e.debit))): $(balance(e.debit))\n",
    "  Credit: $(name(e.credit)) ($(id(e.credit))): $(balance(e.credit))\n")
=#

struct Ledger{B<:Position,ID<:AccountId}
    indexes::Dict{ID,Int}
    accounts::StructArray{Account{B,ID}}

    function Ledger(accounts::Vector{Account{B,ID}}) where {B<:Position,ID<:AccountId}
        indexes = Dict{ID,Int}()
        for (index, account) in enumerate(accounts)
            indexes[id(account)] = index
        end
        new{B,ID}(indexes, StructArray(accounts))
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

#=
function example()
    group = AccountInfo(Credit, Account(AccountId("0000000"), USD(0)), "Account Group")
    assets = AccountInfo(Debit, Account(AccountId("1000000"), USD(0)), "Assets", group)
    liabilities = AccountInfo(Credit, Account(AccountId("2000000"), USD(0)), "Liabilities", group)
    cash = AccountInfo(Debit, Account(AccountId("1010000"), USD(0)), "Cash", assets)
    payable = AccountInfo(Credit, Account(AccountId("2010000"), USD(0)), "Accounts Payable", liabilities)

    entry = Entry(cash, payable)
    return group, assets, liabilities, cash, payable, entry
end
=#

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
