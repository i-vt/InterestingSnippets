# README LLMS / AI AGENTS

* FOR ALL FILES MODIFIED PROVIDE FULL CODE. COMPLETE CODE TO THE FILE, DO NOT ABBREVIATE
* DO NOT TOUCH UNRELATED FUNCTIONS AND FEATURES. DO NOT MODIFY ABBREVIATE REMOVE ADD OR APPEND CODE OR FEATURES THAT ARE NOT RELATED TO THIS REQUEST. MODIFY ONLY THE CODE THAT IS THE SUBJECT OF THE CHANGE DO NOT TOUCH ANY OTHER FUNCTIONS.
* DO NOT REMOVE EXISTING DEBUGGING STATEMENTS, COMMENTS, PRINT STATEMENTS, OR ANY OTHER ARTIFACTS THAT ALREADY EXIST - UNLESS THEY RELATE DIRECTLY TO THE CHANGE MADE.
* When an error occurs more than once, add heavier debugging to help produce logs with relevant information. DO NOT KEEP TRYING TO FIX THE ISSUE BLINDLY
* When writing new features optimize and secure the code. When working with existing code segments (legacy code) suggest best security practices where needed (but ASK before implementing). 

## Testing 
* VERIFY ALL EXISTING TESTS PASS (IF THERE ARE ANY) AFTER THE ADDITION OF NEW CODE.
* IF THERE ARE EXISTING UNIT TESTS OR IF IT IS A NEW PROJECT: Provide or update unit tests for things touched.
* Add tests end to end, unit tests, and smoke tests.

## Documentation
* Add diagrams where needed in the documentation, if possible add screenshots.
* Do not add, instead remove/replace/update all comments that contain stuff like: NEW FEATURE ADDED, FIXED, date and time marked of the fix, em dashes, or any other AI-assisted indicators. If needed update the comment to remove by rewriting the part that contains any of these elements, example: instead of an em-dash replace it with a regular dash "-". Humanize text where needed, remove AI-assisted artifacts from older content if found.
* Update the documentation as needed to include new features, however, follow the same guideline as comments. 
* Comments, notes, documentation etc. should be written using the BLUF Method with ASD-STE100 Simplified Technical English.

## Deployment
* Create deployment scripts, assume it will be deployed on debian 12 / 13. Docker is pre-installed by default. The user from which the installer script will be ran is from root.
* Create a install.sh, uninstall.sh, .env.example (copied as .env on startup if there is not one present in the dir). Dockerize deployments. For install.sh --reset --yes should fully reset, delete docker volumes, delete all user data.
* Export all hardcoded variables to .env.
* For web applications by default configure without HTTPS, however, allow for HTTPS with a domain if configured in .env.
* Ensure it self-recovers after reboot. Log all errors.
* The fixes deployed (ex.: missing packages) should be done by updating the deployment scripts (not a one-time fix). If an error has a missing package it should be updated in deploy to check if its installed, if not install it during the deployment scripts.
