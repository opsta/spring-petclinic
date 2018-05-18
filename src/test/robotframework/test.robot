*** Settings ***
Library  SeleniumLibrary

*** Variables ***
${BROWSER}  %{BROWSER}

*** Testcases ***
Test Home Page
  Open Browser  localhost  ${BROWSER}
  Page Should Contain  Welcome
  Capture Page Screenshot
  [Teardown]  Close Browser
