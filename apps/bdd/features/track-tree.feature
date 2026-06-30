Feature: The user can track tree on greenstand

  Scenario: The organization A user can track a tree and sell its token
    Given I am on the admin panel website
    When I register by my Gmail account
    Then I am on the home page
    When I click the "apply organization" button
    Then I am on the application page
    When I fill the form and submit
    Then I read notification "Now you have become an organization"
    When I click "Share App"
    Then I am on the Share App page and I can see "Link" & "QR code"
    When I share the link with my planter
    Then My planter can install the app and upload a tree
    When I am on the verify page
    Then I can see the tree uploaded by the planter
    Then I can approve the tree
    Then I can see the tree on webmap
    When I as organization user log into the wallet app
    Then I can see a new token shows up
    When I click the token link
    Then I can see the token on webmap and it is bound to the tree uploaded and approved
    Given I am the administrator of greenstand
    When I log into admin panel
    Then I can go to the organization page and find the org A
    Then I can "Enable token trading" for the organization A
    When I log into the wallet app
    And go to the "buy a token" page
    Then I can see the token listed in the list
    When I click the token link
    Then I can see the token details
    And I can see the token B belongs to A
    Given I am a user without registration on Greenstand
    When I register and log into the wallet app
    And create a new wallet
    And click "Buy a token"
    Then I should see token B on the list
    And I can buy token B with my credit card
    And See my token on wallet
    # Settlement leg: the buyer's payment must reach organization A.
    # The card is charged once and split: a Greenstand platform fee is
    # withheld, and the remainder is credited to organization A, which can
    # then withdraw it to its bank account.
    Given I am organization A
    When I log into the wallet app
    Then token B is no longer in my wallet
    When I go to the "Sales" page
    Then I can see token B was sold to the buyer
    And I can see the sale amount credited to my balance, minus the Greenstand platform fee
    When I link my bank account
    And I request a payout of my available balance
    Then I can see the payout is processing
    And the funds are transferred to my linked bank account
    And my available balance is reduced by the payout amount

