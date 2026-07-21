@skip
Feature: Seniaty Story

  Scenario: Seniaty gets paid for what she planted
    Given a user E hasn't registered an account on Greenstand
    When on the admin panel login page
    And user E registers and logs in
    Then on the org application page
    When user E fills the form and submits
    Then user E becomes org E immediately
    When on the share app page
    And user E downloads the QR code
    And org E shares the QR code to Seniaty on her mobile phone
    And Seniaty taps the link on her phone
    Then the link navigates to Google Play's Treetracker page
    When Seniaty installs the app and opens it
    And Seniaty fills the onboarding page and jumps to the home page
    And Seniaty taps the track tree button
    Then on the organization page, the org E name is already displayed, meaning Seniaty is automatically bound to E
    When Seniaty takes captures of trees
    And Seniaty uploads the captures
    Then user E logs into the admin panel and jumps to the verify page
    And user E sees the new captures uploaded by Seniaty
    And user E approves the good trees
    When user E goes to the 'apply to become token vendor' page, and goes through the steps by providing bank info and completing the Stripe integration steps
    Then admin user S logs into the admin panel
    And admin user S goes to the organization management page
    And admin user S finds org E and clicks through to the detail page for E
    And on the 'token market' area, the user's bank and other necessary info is shown, and admin user S clicks 'approve'
    When user D, a new user with no account on Greenstand, registers and logs in to the wallet app
    And user D creates a wallet named D1-wallet
    And user D clicks 'buy a token'
    And user D finds Seniaty's token in the list and buys it with a credit card via Stripe, receiving the token in the wallet
    Then user E receives the money in his bank account
    And user E pays Seniaty outside the Greenstand platform in any possible way
