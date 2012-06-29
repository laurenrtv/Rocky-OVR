Feature: Step 2
  In order to provide personal information
  As a registrant
  I want to enter name, address
  
    Scenario: first visit
      Given I have completed step 1
      When I go to the step 2 page
       And I select "Mr." from "title"
       And I fill in "first" with "John"
       And I fill in "last" with "Public"
       And I fill in "address" with "123 Market St."
       And I fill in "city" with "Pittsburgh"
       And I press "registrant_submit"
      Then I should see "Additional Registration Information"
    
      
    Scenario: default mailing state to home state
      Given I have completed step 1
      When I go to the step 2 page
      Then I should see "Pennsylvania" in select box "registrant_mailing_state_abbrev"
  
    
    Scenario Outline: fields for a <state> state resident with no javascript
      Given I have completed step 1 as a resident of "<state>" state without javascript
      When I go to the step 2 page
      Then I should not see a field for "Phone"
      And I should see a field for "Address"
      And I should see a field for "Race"
      
      Examples:
        | state      |
        | Washington |
        | Arizona    |
    
    
    Scenario Outline: fields for a <state> state resident
      Given I have completed step 1 as a resident of "<state>" state
      When I go to the step 2 page
      Then I should see a field for "Phone"
      And I should see a field for "Type"
      And I should see a checkbox for "Send me txt messages from Rock the Vote"
      And I should see a checkbox for "Receive emails from Rock the Vote"
      And I should see a field for "I have a valid <state_abbr> state ID or driver's license"
      And I should see a field for "I do not have a valid <state_abbr> state ID or driver's license"
      And I should see a button for "Next Step >"
      And I should see "You may be eligible to finish your registration using the state of <state>'s paperless voter registration system."
      And I should see a button for "Let me finish my paperless registration with the state of <state>." 
      And I should see a button for "Finish my registration with Rock the Vote."
      
      Examples:
        | state      | state_abbr |
        | Washington | WA         |
        | Arizona    | AZ         |
      
    
    Scenario Outline: fields for a <state> state resident with a partner
      Given the following partner exists:
        | name           | rtv_sms_opt_in | partner_sms_opt_in | rtv_email_opt_in | partner_email_opt_in |
        | Opt-in Partner | true           | true               | true             | true                 |  
      And I have completed step 1 as a resident of "<state>" state from that partner
      When I go to the step 2 page
      Then I should see a button for "Finish my registration with Rock the Vote and Opt-in Partner."
      And I should see a checkbox for "Send me txt messages from Rock the Vote"
      And I should see a checkbox for "registrant_partner_opt_in_sms"
      And I should see a checkbox for "Receive emails from Rock the Vote"
      And I should see a checkbox for "registrant_partner_opt_in_email"
      When I select "Mr." from "title"
      And I fill in "first" with "John"
      And I fill in "last" with "Public"
      And I choose "I have a valid <state_abbr> state ID or driver's license"
      And I press "registrant_state_online_registration"
      Then I should see "You can complete a paperless registration using the form below. If your driver's license is invalid or there is some other issue with the form, you can also finish your registration with Rock the Vote and Opt-in Partner"
      And I should see a link for "finish your registration with Rock the Vote and Opt-in Partner"
      And I should see an iFrame for the <state> State online system
    
      Examples:
        | state      | state_abbr |
        | Washington | WA         |
        | Arizona    | AZ         |
    
    
    Scenario Outline: has_license field is required
      Given I have completed step 1 as a resident of "<state>" state
      When I go to the step 2 page
      And I press "registrant_submit"
      Then I should see "Please indicate whether you have a valid state license"
    
      Examples:
        | state      |
        | Washington |
        | Arizona    |
    
    
    Scenario Outline: <state> resident selects to finish paperless registration with the state of <state>
      Given I have completed step 1 as a resident of "<state>" state
      When I go to the step 2 page
      And I select "Mr." from "title"
      And I fill in "first" with "John"
      And I fill in "last" with "Public"
      And I choose "I have a valid <state_abbr> state ID or driver's license"
      And I press "registrant_state_online_registration"
      Then I should see "You can complete a paperless registration using the form below. If your driver's license is invalid or there is some other issue with the form, you can also finish your registration with Rock the Vote"
      And I should see a link for "finish your registration with Rock the Vote"
      And I should see an iFrame for the <state> State online system

      Examples:
        | state      | state_abbr |
        | Washington | WA         |
        | Arizona    | AZ         |

    
    Scenario Outline: <state> resident selects to finish registration with Rock the Vote
      Given I have completed step 1 as a resident of "<state>" state
      When I go to the step 2 page
      And I select "Mr." from "title"
      And I fill in "first" with "John"
      And I fill in "last" with "Public"
      And I choose "I have a valid <state_abbr> state ID or driver's license"
      And I press "registrant_skip_state_online_registration"
      Then I should see "Additional Registration Information"
      And I should see a field for "Address"
      And I should see a field for "registrant_home_unit"
      And I should see a field for "City"
      And I should see a field for "State"
      And I should see a field for "ZIP code"
      And I should see a checkbox for "registrant_has_mailing_address"
      And I should see a field for "Race"
      And I should not see a field for "Phone"
      And I should not see a field for "Type"
      And I should not see a field for "Send me txt messages from Rock the Vote"
      
      Examples:
        | state      | state_abbr |
        | Washington | WA         |
        | Arizona    | AZ         |
      