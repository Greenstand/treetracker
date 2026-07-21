@skip
Feature: Treetracker organization binding
We need to bind the Treetracker user/planter to an organization, so we can attach the capture by this user to a correct organization. For now the administrator have to manually find the planter’s organization and set the binding on admin panel, with this feature, we can relief this burden from admin and improve the user experience for the user.

	Scenario: User can install app and set the binding in the app.
		Given an user haven’t installed the Treetracker app
		When the organization X share the link to user by mobile phone
		And the user tap the link on his/her phone
		Then the link navigate to Google Play’s Treetracker page
		When the user install the app and open it
		And fill the onboarding page and jump to home page
		And tap the track tree button
		Then on the organization page, the org X name is displayed on the page  already, means the user is automatically bound to X

	Scenario: User can open the link on Treetracker and bind to org 
		Given an user already installed Treetracker app
		When the organization X shares the link to user by mobile phone
		And the user tap the link on his/her phone
		Then the link navigates to Treetracker app and open it
		When the user jump to home page and tap track a tree
		Then on the organization page, the org X name is displayed on the page  already, means the user is automatically bound to X
