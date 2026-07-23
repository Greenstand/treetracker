@skip
Feature: Seniaty Story V1.0

  Scenario: Seniaty gets paid for what she planted
    Given a user E hasn't registered an account on Greenstand
    Given Seniaty has hasn't downloaded the app or registered an account on Greenstand     
    When on the admin panel login page
    And user E registers and logs in
    Then on the org application page
    When user E fills the form and submits
    Then user E becomes org E immediately
    When on the share app page
    And user E copies the org E link or downloads org E QR code  
    And user E shares the QR code to Seniaty on her mobile phone
    And Seniaty taps the link on her phone
    Then the link navigates to Google Play's Treetracker page
    When Seniaty installs the app and opens it
    And Seniaty fills the onboarding page and jumps to the home page
    And Seniaty taps the track tree button
    Then Seniaty takes captures of trees
    Then Seniaty taps on the send/upload captures button
    Then on the destination page, the org E name is already displayed meaning 
    Then Seniaty confirms and sends captures to org E
    And Seniaty's captures are uploaded to her wallet account with a request to send org E
    Then org e logs into the admin panel and jumps to the verify page
    And user E sees the new captures uploaded by Seniaty
    And user E approves captures (moves captures into org e) or rejects the captures
    Then Seniaty is notified on her app of the status of her captures (approved or rejected)
    Then Seniaty reviews reason for rejected captures, deletes rejected captures and retakes rejected captures
    Then Seniaty taps on the send/upload captures button and process continues
    When user E goes to the 'sell token' page, and goes through the steps by providing bank info and completing the Stripe integration steps
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
*note grow's 
