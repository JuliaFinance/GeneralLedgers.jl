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

abstract type Identifier end
struct AccountId <: Identifier
    value::UUID
end
AccountId() = AccountId(uuid4())

struct AccountCode
    value::String
end

abstract type AccountType end
struct Credit <: AccountType end
struct Debit <: AccountType end

mutable struct Account{P<:Position}
    id::AccountId
    balance::P
end
Account(balance::Position) = Account(AccountId(), balance)

abstract type AccountNode end
struct AccountInfo{AT<:AccountType,A<:Account} <: AccountNode
    account::A
    code::AccountCode
    name::String

    function AccountInfo(::Type{T}, account, code, name) where {T<:AccountType}
        return new{T}(account, code, name)
    end
end

struct AccountGroup{AT<:AccountType} <: AccountNode
    code::AccountCode
    name::String
    parent::Union{Nothing,AccountGroup{<:AccountType}}
    subaccounts::Vector{AccountInfo}
    subgroups::Vector{AccountGroup}

    function AccountGroup(::Type{T}, account, name, parent=nothing) where {T<:AccountType}
        new{T}(account, code, name, parent, Vector{AccountInfo}(), Vector{AccountGroup}())
    end
end

# Identity function (to make code more generic)
account(acc::Account) = acc
account(info::AccountInfo) = info.account

account_type(::Union{AccountInfo{AT},AccountGroup{AT}}) where {AT} = AT
code(acc::Union{<:AccountInfo,<:AccountGroup}) = acc.code
name(acc::Union{<:AccountInfo,<:AccountGroup}) = acc.name

parent(group::AccountGroup) = group.parent
subaccounts(group::AccountGroup) = group.subaccounts
subgroups(group::AccountGroup) = group.subgroups

id(acc::Account) = acc.id
id(info::AccountInfo) = id(account(info))

balance(acc::Account) = acc.balance
balance(info::AccountInfo) = balance(account(info))
balance(group::AccountGroup) = 
    sum(map(info->balance(info), subaccounts(group))) + 
    sum(map(grp->balance(grp), subgroups(group)))

instrument(::Account{P}) where {P<:Position} = instrument(P)
instrument(info::AccountInfo) = instrument(account(info))

symbol(::Account{P}) where {P<:Position} = symbol(P)
symbol(info::AccountInfo) = symbol(account(info))

currency(::Account{P}) where {P<:Position} = currency(P)
currency(info::AccountInfo) = currency(account(info))

amount(acc::Account) = amount(balance(acc))
amount(info::AccountInfo) = amount(balance(account(info)))

debit!(acc::Account, amt::Position) = (acc.balance += amt)
credit!(acc::Account, amt::Position) = (acc.balance -= amt)

struct Entry{D<:Account,C<:Account}
    debit::D
    credit::C
end

function post!(entry::Entry, amt::Position)
    debit!(account(entry.debit), amt)
    credit!(account(entry.credit), amt)
    entry
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

function add_account!(ledger::Ledger, acc::Account)
    push!(ledger.accounts, acc)
    ledger.indexes[id(acc)] = length(ledger.accounts)
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

Base.show(io::IO, id::Identifier) = print(io, id.value)
Base.show(io::IO, code::AccountCode) = print(io, code.value)

Base.show(io::IO, ::Type{Debit}) = print(io, "Debit")
Base.show(io::IO, ::Type{Credit}) = print(io, "Credit")

Base.show(io::IO, acc::Account) = print(io, "$(string(id(acc))): $(balance(acc)).")
Base.show(io::IO, info::AccountInfo{Debit}) = print(io, "$(code(info)) - $(name(info)): $(balance(info)).")
Base.show(io::IO, info::AccountInfo{Credit}) = print(io, "$(code(info)) - $(name(info)): $(-balance(info)).")


# AbstractTrees.children(info::AccountInfo) =
#     isempty(subaccounts(info)) ? Vector{AccountInfo}() : subaccounts(info)
# AbstractTrees.printnode(io::IO,info::AccountInfo) =
#     print(io, "$(name(info)) ($(id(info))): $(balance(info))")

# Base.show(io::IO,info::AccountInfo) =
#     isempty(subaccounts(info)) ? printnode(io, info) : print_tree(io, info)

# Base.show(io::IO, e::Entry) =
#     print(io, "Entry:\n", "  Debit: $(e.debit)\n", "  Credit: $(e.credit)")

# function Base.show(io::IO, e::Entry)
#     print(io,
#           "Entry:\n",
#           "  Debit: $(name(e.debit)) ($(id(e.debit))): $(balance(e.debit))\n",
#           "  Credit: $(name(e.credit)) ($(id(e.credit))): $(balance(e.credit))\n")
# end

end # module Ledgers
