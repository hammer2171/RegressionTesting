# MCP Procedure: Create EDM Request

Procedure ID: `create-edm-request-sample-entity`
Application: Oracle EDM epm18-test
URL: `https://epm18-test-a706571.epm.us2.oraclecloud.com/epm`
Mode: Playwright MCP headed
Auth: Use existing Playwright storage state. If prompted, login interactively and record that auth refresh was required.

## Goal

Create a new EDM request in the A_Entry_Entity view using the
Input_EPM_Entity_Base viewpoint and verify the request is created
successfully

## Test Data

- View:A_Entry_Entity
- Viewpoint:Input_EPM_Entity_Base 
- Request title:Create EDM Request base Entity
- Node or hierarchy: Input_EPM_Entity_Base
- Other values: Ledger Number = 0638 , Business Unit = EE - Pole Production

## Preconditions

- Storage state exists or user is available to complete login.  Storage state is located here \\vw058304\C$\RegressionTesting\epm18-test\Playwright\playwright\.auth\user.epm18_test.json
- Required view/viewpoint/data exists.
- Browser should start from the <Folder> URL above, which is https://epm18-test-a706571.epm.us2.oraclecloud.com/epm

## Evidence Checkpoints

- After successful login or landing page load.
- After navigating to the target work area.
- Before submitting or saving changes.
- After final success message or expected result.

## Steps

1. Open the URL - https://epm18-test-a706571.epm.us2.oraclecloud.com/epm
   - Expected: EDM home or landing page is visible.
   - Evidence: screenshot named `01-home.png`.

2. Navigate to `Views` and click the Views link.
   - Expected: `Views` page is visible.
   - Evidence: screenshot named `02-area.png`.

3. Click on the View `A_Entry_Entity`.
   - Expected: `A_Entry_Entity` page is visible.
   - Evidence: screenshot named `03-action.png`.

4. Click on the Viewpoint `Input_EPM_Entity_Base`.
   - Expected: `Input_EPM_Entity_Base` page is visible.
   - Evidence: screenshot named `04-action.png`.
   
5. Start a new request by pressing the New Request button.
   - Expected: New request panel, dialog, or request context is visible.
   - Evidence: screenshot named `05-new-request.png`.

6. Enter request title `Create EDM Request base Entity`.
   - Expected: A_Entry_Entity - Request and a auto-generated number is visibile.
   - Evidence: screenshot named `06-request-title.png`.
   
7. Enter request description `Create a new EDM request in the A_Entry_Entity view using the Input_EPM_Entity_Base viewpoint`.
   - Expected: Request description is visible.
   - Evidence: screenshot named `07-request-description.png`.
   
8. Click the + above the Viewpoint Grid which reads Add Node as you hover over it before clicking it.
   - Expected: Add New and Add From sub menus are visible.
   - Evidence: screenshot named `08-request-addnew.png`.   

9. Click the Add New sub menu from step 8 above.
   - Expected: Ledger Number and Business Unit have a red outline around them in the right hand Properties tab.
   - Evidence: screenshot named `09-request-addnewsub.png`.   
   
10.  Click in the Ledger Number property.
   - Expected: Text 'Select a Node for Ledger Number' appears in a new dialog box.
   - Evidence: screenshot named `10-request-ledgnumbox.png`.  

11.  Enter 0638 in the text box and click on the magnifying glass.
   - Expected: Text 'Select a Node for Ledger Number' appears in a new dialog box.
   - Evidence: screenshot named `11-request-ledgnuminput.png`.     

12.  Click on the 0638 below the searchable text box.
   - Expected: A check mark appears next to the 0638 below the searchable text box and this text 'NOV_Legal_Entity_Ownership >3001CE >0638' appears above the searchable text box.
   - Evidence: screenshot named `12-request-ledgnumcheck.png`. 

13.  Press the Ok button in the lower right corner of the searchable entity dialog.
   - Expected: 0638 now appears in the Ledger Number property.
   - Evidence: screenshot named `13-request-ledgnumprop.png`. 
   
14.  Click in the Business Unit property immediately below the Ledger Number property.
   - Expected: A drop down menuu starting with the text 'EE - Energy Equipment' is visible. 
   - Evidence: screenshot named `14-request-budropdown.png`. 

15.  Scroll down and click on 'EE - Pole Production' in the dropdown menu.
   - Expected: The text 'EE - Pole Production' is now visible in the Business Unit property. 
   - Evidence: screenshot named `15-request-budropdownselect.png`. 
   
16.  Press the 'Submit' button in the area above the Select Viewpoint selectable drop down menu .
   - Expected: 'New Request' button reappears. 
   - Evidence: screenshot named `16-request-submit.png`.    
   
17. Validate the request.
   - Expected: New EPM Entity Name property 'E_0638PD' is now visible and not selectable.
   - Evidence: screenshot named `17-final.png`.

## MCP Notes

- Take a fresh snapshot before interacting with navigation, menus, forms, or dialogs.
- Prefer visible text, accessible labels, and roles over brittle CSS selectors.
- If an element cannot be found, capture a screenshot and page snapshot, then stop as Blocked.
- Record every clicked label and typed value in the run log.

## Do Not

- Do not expose passwords, cookies, storage-state content, or auth headers.
- Do not continue after a failed save/submit unless explicitly instructed.

