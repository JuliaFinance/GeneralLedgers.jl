using Ledgers, Test
using Assets: USD

group, assets, liabilities, cash, payable, entry = Ledgers.example()

@testset "Account creation" begin
    @test id(group) isa AccountId
    @test id(assets) isa AccountId
    @test code(cash).value === "1010000"
    @test name(payable) === "Accounts Payable"
    @test balance(group) === 0USD
    @test balance(assets) === 0USD
    @test balance(liabilities) === 0USD
end

@testset "Post entry" begin
    amt = 10USD
    post!(entry, amt)
    @test balance(group) === 0USD
    @test balance(assets) === amt
    @test balance(liabilities) === -amt
    @test balance(cash) === amt
    @test balance(payable) === -amt
end