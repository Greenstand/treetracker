Feature: The user can track tree on greenstand

  Scenario: The organzation A user can track tree and sale its token
    Given I am on the admin panel website
    When I register by my Gmail account
    Then I am on the home page
    When I click the "apply organzation" button
    Then I am on the application page
    When I fill the form and submit
    Then I read notification "Now you has become an organzation"
    When I click "Share App"
    Then I am on the Share App page and I can see "Link" & "QR code"
    When I share the link with my planter
    Then My planter can install the app and upload tree
    When I am on the verify page
    Then I can see the tree uploaded by the planter
    Then I can approve the tree
    Then I can see the tree on webmap
    When I as organziation user log into the wallet app
    Then I can see a new token shows up 
    When I click the token link
    Then I can see the token on webmap and it is bind to the tree uploaded and approved
    Given I am the adminstrator of greenstand
    When I log into admin panel
    Then I can go to the organization page and find the org A
    Then I can "Enable token trading" for the organzation A
    When I log into the wallet app 
    And go to the "buy a token" page
    Then I can see the token listed in the list
    When I click the token link 
    Then I can see the token details
    And I can see the token B belongs to A
    Given I am an user without registeration on Greestand
    When I register and log into the wallet app
    And create a new wallet
    And click "Buy a token"
    Then I should see token B on the list
    And I can buy token B with my credit card
    And See my token on wallet
    Given I am organzation A
    When I ??? 
    
