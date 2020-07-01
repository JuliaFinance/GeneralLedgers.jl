"""
Ledgers

This package provides support for general financial ledgers

See README.md for the full documentation

Copyright 2019-2020, Eric Forgy, Scott P. Jones and other contributors

Licensed under MIT License, see LICENSE.md
"""
module Ledgers

using UUIDs, StructArrays, AbstractTrees
using Instruments
import Instruments: instrument, symbol, amount, name, currency
using Assets: USD

export Account, Ledger, Entry, AccountId, AccountCode, AccountInfo, AccountGroup
export id, balance, credit!, debit!, post!, instrument, symbol, amount, code, name, currency
export parent, subaccounts, subgroups

abstract type Identifier end

struct AccountId <: Identifier
    value::UUID
end

AccountId() = AccountId(uuid4())

struct AccountCode
    value::String
end

abstract type AccountType{B <: Position} end

mutable struct Account{B <: Position} <: AccountType{B}
    id::AccountId
    balance::B
end

Account(balance::Position) = Account{typeof(balance)}(AccountId(), balance)

abstract type AccountNode{B <: Position} <: AccountType{B} end

struct AccountInfo{B <: Position} <: AccountNode{B}
    account::Account{B}
    code::AccountCode
    name::String
    isdebit::Bool

    function AccountInfo{B}(account::Account{B}, code, name, isdebit=true, parent=nothing) where {B <: Position}
        acc = new{B}(account, code, name, isdebit)
        parent === nothing || push!(parent.subaccounts, acc)
        acc
    end
end

AccountInfo(account::Account{B}, code, name, isdebit=true, parent=nothing) where {B <: Position} =
    AccountInfo{B}(account, code, name, isdebit, parent)

struct AccountGroup{B <: Position} <: AccountNode{B}
    id::AccountId
    code::AccountCode
    name::String
    isdebit::Bool
    parent::Union{Nothing,AccountGroup{B}}
    subaccounts::StructArray{AccountInfo{B}}
    subgroups::StructArray{AccountGroup{B}}

    function AccountGroup{B}(
        id,
        code,
        name,
        isdebit=true,
        parent=nothing,
        subaccounts=StructArray(Vector{AccountInfo{B}}()),
        subgroups=StructArray(Vector{AccountGroup{B}}())) where {B <: Position}
        acc = new{B}(id, code, name, isdebit, parent, subaccounts, subgroups)
        parent === nothing || push!(parent.subgroups, acc)
        acc
    end
end

AccountGroup(
    ::B,
    code,
    name,
    isdebit=true,
    parent=nothing, 
    subaccounts=StructArray(Vector{AccountInfo{B}}()),
    subgroups=StructArray(Vector{AccountGroup{B}}())) where {B <: Position} =
    AccountGroup{B}(AccountId(), code, name, isdebit, parent, subaccounts, subgroups)

# Identity function (to make code more generic)
account(acc::AccountType) = acc
account(info::AccountInfo) = info.account

code(acc::AccountNode) = acc.code
name(acc::AccountNode) = acc.name
isdebit(acc::AccountNode) = acc.isdebit

parent(group::AccountGroup) = group.parent
subaccounts(group::AccountGroup) = group.subaccounts
subgroups(group::AccountGroup) = group.subgroups

id(acc::AccountType) = account(acc).id

balance(acc) = account(acc).balance
balance(group::AccountGroup) = isempty(subgroups(group)) ?
    sum(balance.(subaccounts(group))) :
    sum(balance.(subaccounts(group))) + sum(balance.(subgroups(group)))

instrument(::AccountType{B}) where {B <: Position} = instrument(B)

symbol(::AccountType{B}) where {B <: Position} = symbol(B)

currency(::AccountType{B}) where {B <: Position} = currency(B)

amount(acc::AccountType) = amount(balance(acc))

debit!(acc::Account, amt::Position) = (acc.balance += amt)
credit!(acc::Account, amt::Position) = (acc.balance -= amt)

struct Entry{B <: Position}
    debit::AccountInfo{B}
    credit::AccountInfo{B}
end

function post!(entry::Entry, amt::Position)
    debit!(account(entry.debit), amt)
    credit!(account(entry.credit), amt)
    entry
end

struct Ledger{P <: Position}
    indexes::Dict{AccountId,Int}
    accounts::StructArray{Account{P}}

    function Ledger(accounts::Vector{Account{P}}) where {P <: Position}
        indexes = Dict{AccountId,Int}()
        for (index, account) in enumerate(accounts)
            indexes[id(account)] = index
        end
        new{P}(indexes, StructArray(accounts))
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

function example()
    group = AccountGroup(USD(0), AccountCode("0000000"), "Account Group", false)
    assets = AccountGroup(USD(0), AccountCode("1000000"), "Assets", true, group)
    liabilities = AccountGroup(USD(0), AccountCode("2000000"), "Liabilities", false, group)
    cash = AccountInfo(Account(USD(0)), AccountCode("1010000"), "Cash", true, assets)
    payable = AccountInfo(Account(USD(0)), AccountCode("2010000"), "Accounts Payable", false, liabilities)

    entry = Entry(cash, payable)
    group, assets, liabilities, cash, payable, entry
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

Base.show(io::IO, acc::Account) = print(io, "$(string(id(acc))): $(balance(acc))")

Base.show(io::IO, acc::AccountNode) = print_tree(io, acc)

Base.show(io::IO, entry::Entry) = print_tree(io, entry)

AbstractTrees.children(acc::AccountGroup) = vcat(Vector(subgroups(acc)),Vector(subaccounts(acc)))

AbstractTrees.printnode(io::IO, acc::AccountNode) = 
    print(io, "[$(code(acc))] $(name(acc)): $(isdebit(acc) ? balance(acc) : -balance(acc))")

AbstractTrees.children(entry::Entry) = [entry.debit, entry.credit]

AbstractTrees.printnode(io::IO, ::Entry) = print(io, "Entry:")

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
