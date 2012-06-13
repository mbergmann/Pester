$scriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
function Get-GlobalTestResults {
    if ($Global:TestResults -ne $null) {
        return $Global:TestResults
    }

    $testResults = @{}
    $testResults.Categories = @();
    $testResults.CurrentCategory = @{ name = ''; Tests = @() }
    $testResults.TestCount = 0
    $testResults.FailedTestCount = 0
    $testResults.TestDepth = 0


    $Global:TestResults = $testResults
    return $Global:TestResults
}

function Reset-GlobalTestResults {
    $global:TestResults = $null
}

function Write-TestReport {
    $results = $Global:TestResults
    Write-Host Tests completed
    Write-Host Passed: $($results.TestCount - $results.FailedTestsCount) Failed: $($results.FailedTestsCount)
}

function Write-NunitTestReport($results, $outputFile) {
    if($results -eq $null) {
        return;
    }
    $report = @{
        runDate = (Get-Date -format "yyyy-MM-dd")
        runTime = (Get-Date -format "HH:mm:ss")
        total = 0;
        failures = 0;        
    }

    $report.total = $results.TestCount
    $report.failures = $results.FailedTestCount
    $report.TestSuites = (Get-TestSuites $results.Categories)
    $report.testCases = (Get-TestResults $results.Tests)  
    $report.Environment = (Get-RunTimeEnvironment)
    Invoke-Template 'TestResults.template.xml' $report | Set-Content $outputFile -force
}

function Get-TestSuites($categories) {
    $testSuites = ( $categories | %{
        $suite = @{  
            success = "True"
            resultMessage = "Failure"
            totalTime = "0.0"
            name = $_.name
        }
        $suite.testCases = (Get-TestResults $_.Tests)  
        $suite.totalTime = (Get-TestTime $_.Tests)
        $suite.success = (Get-TestSuccess $_.Tests)
        if($suite.success -eq "True") 
        {
            $suite.resultMessage = "Success" 
        }
        Invoke-Template 'TestSuite.template.xml' $suite
    })
    return $testSuites
}

function Get-TestTime($tests) {
    $totalTime = 0;
    $tests | %{
        $totalTime += $_.time
    }
    return $totalTime;
}

function Get-TestSuccess($tests) {
    $success = "True"
    $tests | %{
        if($_.sucess -eq $false) {
            $success = "False"
        }
    }
    return $success;
}


function Get-Template($fileName) {
    $path = '.\templates'
    if($Global:ModulePath) {
        $path = $global:ModulePath + '\templates'
    }    
    return Get-Content ("$path\$filename")
}

function Get-TestResults($tests) {
    $testCaseXmls = $tests | %{ 
        $result = $_
        if($result.success) {
            Invoke-Template 'TestCaseSuccess.template.xml' $result
        }
        else {
            Invoke-Template  'TestCaseFailure.template.xml' $result
        }
    }
    return $testCaseXmls
}

function Get-RunTimeEnvironment() {
    $osSystemInformation = (Get-WmiObject -computer 'localhost' -cl Win32_OperatingSystem)
    $currentCulture = ([System.Threading.Thread]::CurrentThread.CurrentCulture).Name
    $data = @{
        osVersion = $osSystemInformation.Version
        platform = $osSystemInformation.Name
        runPath = (Get-Location).Path
        machineName = $env:ComputerName
        userName = $env:Username
        userDomain = $env:userDomain
        currentCulture = $currentCulture
    }
    return Invoke-Template 'TestEnvironment.template.xml' $data
}

function Get-ReplacementArgs($template, $data) {
   $replacements = ($data.keys | %{
            if($template -match "@@$_@@") {
                $value = $data.$_ -replace "``", "" -replace "`'", ""
                "-replace '@@$_@@', '$value'"
            }
        })
   return $replacements
}

function Invoke-Template($templatName, $data) {
    $template = Get-Template $templatName
    $replacments = Get-ReplacementArgs $template $data
    return Invoke-Expression "`$template $replacments"
}

function Exit-WithCode {
    $failedTestCount = $Global:TestResults.FailedTests.Length
    $host.SetShouldExit($failedTestCount)
}

