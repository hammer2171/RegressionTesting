Persona - You are an Oracle EDM Principal Product Engineer, Microsoft Powershell Engineer, and Playwright Automation Engineer.

We will use Playwright, the EDM cloud Rest Apis from Oracle, Poersell, Playwright, and the Playwright MCP server to write tests for our monthly regression testing.

Use the boostrap procedure found in C:\Playwright_development and use the folder C:\Playwright_development\28_test_FINPLAN as the basis of the tests for Playwright to be boot strapped to C:\RegressionTesting\epm18-test
- name the first folder Playwright - it will sit under this folder C:\RegressionTesting\epm18-test on \\vw058304\C$ ;
All files referenced in this md will be located on this server.  In the boot strap do not copy over the runs folder or tests related to 28_test, only the folder structure - and 
fixtures, helpers, evidence procedures, loggig, run folder creation methodology.

We will use solid state storage for authentication in Playwright, and this folder should allow for multiple .env and auths, etc...

I have placed some sample ps1 scripts in C:\RegressionTesting\epm18-test\reference, which will give you information on how our 
Rest APIs are called with authentication and the passing of the auth headers, logging, paramterization of code snippets to run the test, etc...

https://epm18-test-a706571.epm.us2.oraclecloud.com is the URL for epm18-test

https://docs.oracle.com/en/cloud/saas/enterprise-data-management-cloud/edmra/edmcs_url_structure_rest_api_resource.html - is a link
to the documentation for EDM Rest Apis by Oracle.

All scripts should be logged, parameterized, include a runs folder - that is dat time stamped, and includes the logging for the run.

I have set up the scaffold for C:\RegressionTesting\epm18-test, the following folders have already been created inder this folder:

      documentation
	  reference
      scripts
      Runs
      Playwright

C:\RegressionTesting\epm18-test\documentation - contains:
EDM_Regression_Testing.xlsx - list of tasks to accomplish for testing and which need to be Playwright vs scripted via the REST APIs.


I want to heavily use the Playwright MCP server in these tests where I just write in an md what you are to do and you use the MCP in headed mode to do it.  Please run
all scripts tunneled to \\vw058304\c$ - also create snippets of code for me to run and I may log on to the server and run them.	  
