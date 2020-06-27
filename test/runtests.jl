using Ledgers, Test
using Assets: USD

group = AccountInfo(Credit, Account(AccountId("0000000"), USD(0)), "Account Group")
assets = AccountInfo(Debit, Account(AccountId("1000000"), USD(0)),
                     "Assets", group)
liabilities = AccountInfo(Credit, Account(AccountId("2000000"), USD(0)),
                          "Liabilities", group)
cash = AccountInfo(Debit, Account(AccountId("1010000"), USD(0)),
                   "Cash", assets)
payable = AccountInfo(Credit, Account(AccountId("2010000"), USD(0)),
                      "Accounts Payable", liabilities)

entry = Entry(cash, payable)

@testset "Account creation" begin
    @test id(group) isa AccountId
    @test id(assets) isa AccountId
    @test id(cash).value == "1010000"
end
