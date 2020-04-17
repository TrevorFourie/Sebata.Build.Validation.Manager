Clear
Clear-History
#PARAMETERS
$orgName				= Get-VstsInput -Name azOrgName -Require
$organisationName		= "https://dev.azure.com/$($orgName)/";
$projectName			= Get-VstsInput -Name azProjectName -Require
$repositoryName			= Get-VstsInput -Name azRepoName -Require
$definitions			= Get-VstsInput -Name azBuildDefId -Require
[int]$buildAttempts		= Get-VstsInput -Name azBuildAttempts -Require
[string]$branchInput	= Get-VstsInput -Name azBranchName -Require
[string]$MailSend		= Get-VstsInput -Name azSendMail
[bool]$MailSend			= if ($MailSend -eq "false"){0}else{1};

Function ThrowError([string]$variable, [string]$errMessage)
{
    if ([System.String]::IsNullOrWhiteSpace($variable))
    { 
        Write-Host "##[error] $($errMessage)" -ForeGroundColor Red;
        Write-Output "##vso[task.complete result=Failed;]DONE"
        #Exit 1;
    }
}
#VALIDATE ALL FIELDS ARE POPULATED
ThrowError $($orgName) "No Organisation name was specified. Verify that the organisation name is correct and not empty."
ThrowError $($projectName) "No Project name was specified. Verify that the name of the project is correct and that the project exists on the '$($orgName)' Azure DevOps Server."
ThrowError $($repositoryName) "No Repository name was specified. Verify that the repository name is correct and exists on the '$($projectName)' project."
ThrowError $($definitions) "No build definition was specified. Verify that there is at least 1 build definition specified."
ThrowError $($branchInput) "No branch name was specified. Verify that the branch name is correct and exists on the '$($repositoryName)' repository."
ThrowError $($buildAttempts) "No build attempts specified. Verify that at least 1 build attempt is made."

#AUTHENTICATION
$devOpsHeader = @{ Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN" }

$repoURL  = "$($organisationName)$($projectName)/_apis/git/repositories?api-version=4.1"
#VALIDATE ORGANISATION AND PROJECT DOES EXIST
    Try 
    {
      $repoData = Invoke-RestMethod -Uri $repoURL -Headers $devOpsHeader
    } 
    Catch 
    {
      Write-Host "##[error] $($_.Exception.Message)" -ForegroundColor Red;
      Write-Host "##[error] The project '$($projectName)' or Organisation '$($orgName)' could not be found. Verify that the name of the project and organisation is correct and that the project exists on the '$($orgName)' Azure DevOps Server." -ForeGroundColor Red;
      Write-Output "##vso[task.complete result=Failed;]DONE"
      #Exit 1;
    } 

$RepoID = $repoData.value.id;
$RepoName = $repoData.value.name

#VALIDATE REPOSITORY DOES EXIST
if($repositoryName -ne $RepoName)
{
    Write-Host "##[error] The repository '$($repositoryName)' could not be found. Verify that the name of the repository is correct and that the repository exists on the '$($projectName)' project." -ForeGroundColor Red;
    Write-Output "##vso[task.complete result=Failed;]DONE"
    #Exit 1;
}
[string]$gitRepoId = "$($RepoID)"

if($MailSend)
{
	$emailSmtpServer = Get-VstsInput -Name azSmtpServer -Require
	$emailSmtpServerPort = Get-VstsInput -Name azSmtpPort -Require
	$emailSmtpUser = Get-VstsInput -Name azSmtpUser -Require
	$emailSmtpPass = Get-VstsInput -Name azSmtpPass -Require
	$emailFrom = "Azure Devops <$($emailSmtpUser)>" 
	$emailToInput = Get-VstsInput -Name azSmtpTo -Require
	$emailTo = $emailToInput -replace ";", "`,"

	#VALIDATE ALL FIELDS ARE POPULATED WHEN MAIL SELECTED
    ThrowError $($emailSmtpServer) "No SMTP Mail Server Specified."
    ThrowError $($emailSmtpServerPort) "No SMTP Mail Server Port Specified."
    ThrowError $($emailSmtpUser) "No SMTP Mail Server User Name Specified."
    ThrowError $($emailSmtpPass) "No SMTP Mail Server User Password Specified."
    ThrowError $($emailToInput) "No E-Mails address To someone specified."
}

[string]$branch = "refs/heads/$($branchInput)"
[string]$ReleaseVersion = $env:RELEASE_RELEASENAME
[string]$ReleaseDefinitionName =$env:RELEASE_DEFINITIONNAME
[string]$RELEASE_ENVIRONMENTNAME = $env:RELEASE_ENVIRONMENTNAME
[string]$ReleaseId = $env:RELEASE_RELEASEID

$defNumbersNew = "";

#GET BUILD DEFINITION ID'S
$buildGetURL  = "$($organisationName)$($projectName)/_apis/build/definitions?api-version=5.1"
$buildGetData = Invoke-RestMethod -Uri $buildGetURL -Headers $devOpsHeader 

$defCount = $definitions.split(";")
[int]$defTotal = $defCount.Count
$match = 0;   
for($i = 0; $i -le [int]$defTotal; $i++)
{
    $getDefName = $defCount[$i]
    foreach($buildVal in $buildGetData.value)
    {
        if($getDefName -eq $buildVal.name)
        {
            $defNumbersNew += "$($buildVal.id)$(if($i -lt ($defTotal - 1)){";"})";
            $match++
        }
    }
}

if($match -eq 0)
{
    Write-Host "##[error] None of the following builds, $($definitions -replace ";", ", "), were not found in the repository '$($repositoryName)'" -ForegroundColor Red;
    Write-Output "##vso[task.complete result=Failed;]DONE"
    #Exit 1;
}

#Clear Variables
$buildOutPut = "";
$buildValidate = "";
$buildStatus = "";
$buildFailed = "";

$defNumbers = $defNumbersNew
$defNumbers = $defNumbers.Split(";")

[int]$TotalRec = [int]$($buildAttempts)*[int]$($defNumbers.Count);
$RetRes = '$top';
$RetResults = "$($RetRes)=$($TotalRec)";
$definitions = $defNumbersNew  -replace ";", ",";
$statusFilter = "all"
$maxBuildsPerDefinition = "$($buildAttempts)"


$buildURL  = "$($organisationName)$($projectName)/_apis/build/builds?$($RetResults)&definitions=$($definitions)&maxBuildsPerDefinition=$($maxBuildsPerDefinition)&queryOrder=queueTimeDescending&statusFilter=$($statusFilter)&branchName=$($branch)&api-version=5.1"
$buildData = Invoke-RestMethod -Uri $buildURL -Headers $devOpsHeader 

$count = 1;
if ($buildData.count -gt 0)
{
    Write-Host "Validating builds for Release $($ReleaseVersion) from branch '$($branchInput)'";
    Write-Host "Builds for $($ReleaseVersion) > $($branchInput) branch";
    Write-Host "------------------------------------------------------------------------------";
    foreach($build in $buildData.value)
     {
        $BuildName = $($build.definition.name);
        [datetime]$StartTime = $build.startTime;


        if ($build.result -eq "failed" -or $build.status -eq "inProgress")
        {
            if($build.status -eq "inProgress")
            {
                $BuildReturn = "<td style=""position: relative; float: left; width: auto; text-align: left;"">: $($build.buildNumber)</td><td style="" position: relative; float: left; width: 70px; text-align: center; color: Orange;"">In Progress</td>"
                Write-Host "##[Warning] Build Result: $($build.status.ToUpperInvariant()) - $($BuildName) - $($build.buildNumber)." -ForegroundColor DarkYellow;
                $buildStatus = "inProgress"
            }
            else
            {
                $BuildReturn = "<td style=""position: relative; float: left; width: auto; text-align: left;"">: $($build.buildNumber)</td><td style="" position: relative; float: left; width: 70px; text-align: center; color: red;"">Failed</td>"
                Write-Host "##[error] Build Result: $($build.result.ToUpperInvariant()) - $($BuildName) - $($build.buildNumber)." -ForegroundColor Red;
                $buildFailed = "Failed"
            }
            
            $buildOutPut += "<tr style=""width: 100%; padding-bottom: 5px;""><td style=""position: relative; float: left; width: auto; text-align: left;"">- $($BuildName)</td>$($BuildReturn)<td style=""position: relative; float: left; width: 80px; text-align: center;"">(<a target="" _blank"" href="" $($build._links.web.href)"">View Build</a>)</td></tr>";
            $buildValidate = "Error";
            $count++
        }
        else
        {
            Write-Host "Build Result: $($build.result.ToUpperInvariant()) - $($BuildName) - $($build.buildNumber).";
        }
    }
    Write-Host "------------------------------------------------------------------------------";
}
else
{
    Write-Host "##[error] The branch '$($branchInput)' could not be found. Verify that the name of the branch is correct and that the branch exists on the '$($repositoryName)' reporsitory." -ForegroundColor Red;
    Write-Output "##vso[task.complete result=Failed;]DONE"
}

#EMAIL SUBJECT
$smtpSubject = "[Deployment failed] $($ReleaseDefinitionName) > $($ReleaseVersion) : $($RELEASE_ENVIRONMENTNAME)";
#EMAIL BODY
$Body = (
    "<html>
    <head>
        <style>
            * {
                font-family: ""Segoe UI"";
                font-size: 13px;
            }

            body, html {
                width: 100%;
                padding: 0;
                margin: 0;
                background-color: #fafafa;
                text-align: center
            }

            a {
                color: #0078d4;
                text-decoration: none;
            }

                a:hover {
                    text-decoration: underline;
                }
        </style>
    </head>
    <body>
        <table style=""text-align: center; margin-left: auto; margin-right: auto; max-width: 60%; padding: 10px;"">
            <tr style=""width: 100%;"">
                <td style=""font-size: 16px; font-weight: 400; color: #646464; text-align: right;"">Sebata - Azure <span style=""font-size: 16px; color: #0078d4;"">DevOps</span></td>
            </tr>
            <tr style=""width: 100%;"">
                <td style=""font-size: 28px; font-weight: 200; padding: 10px; color: #646464; text-align:center;"">$($ReleaseDefinitionName) > $($ReleaseVersion) > $($RELEASE_ENVIRONMENTNAME) > Failed</td>
            </tr>
            <tr style=""width: 100%; border: solid 2px rgba(103, 103, 103, 0.10); padding: 10px;"">
                <td style=""width: 100%; background-color: #fff; margin-bottom: 15px;"">
                    <table style=""padding: 10px; width: 100%;"">
                        <tr>
                            <td colspan=""2"" style=""font-weight: bold; font-size: 28px; text-align: center; padding-bottom: 15px;"">DEPLOYMENT TO $($RELEASE_ENVIRONMENTNAME) FAILED.</td>
                        </tr>
                        <tr>
                            <td colspan=""2"" style="" font-size: 20px; font-weight: bold; padding-bottom: 10px; color: #646464; text-align: left;"">SUMMARY</td>
                        </tr>
                        <tr>
                            <td style=""position: relative; float: left; width: 80px; text-align: left;"">Reason</td>
                            <td style=""position: relative; float: left; text-align: left;"">: <b>Failed/In Progress</b> Builds</td>
                        </tr>
                        <tr>
                            <td style=""position: relative; float: left; width: 80px; text-align: left;"">Environment</td>
                            <td style=""position: relative; float: left; text-align: left;"">: $($RELEASE_ENVIRONMENTNAME)</td>
                        </tr>
                        <tr>
                            <td style=""position: relative; float: left; width: 80px; text-align: left;"">Branch</td>
                            <td style=""position: relative; float: left; text-align: left;"">: $($branchInput)</td>
                        </tr>
                        <tr>
                            <td style=""position: relative; float: left; width: 80px; text-align: left;"">Release</td>
                            <td style="" position: relative; float: left; text-align: left;"">: $($ReleaseVersion)</td>
                        </tr>
                    </table>
                </td>
            </tr>
            <tr><td>&nbsp;</td></tr>
            <tr style=""width: 100%; border: solid 2px rgba(103, 103, 103, 0.10); padding: 10px;"">
                <td style=""width: 100%; background-color: #fff; margin-bottom: 15px;"">
                    <table style=""width: 100%; padding: 10px;"">
                        <tr>
                            <td colspan=""4"" style=""font-size: 20px; font-weight: bold; padding-bottom: 10px; color: #646464; text-align: left;"">DETAILS</td>
                        </tr>
                        $($buildOutPut)
                    </table>
                </td>
            </tr>
            <tr><td>&nbsp;</td></tr>
            <tr style=""width: 100%; border: solid 2px rgba(103, 103, 103, 0.10); padding: 10px;"">
                <td style=""width: 100%; background-color: #fff; margin-bottom: 15px;"">
                    <table style=""width: 100%; padding: 5px;"">
                        <tr style=""display: flex; width: 100%;"">
                            <td style=""position: relative; float: left; text-align: left; font-size: 13px;""><a target="" _blank"" style="" font-size: 13px;"" href=""$($organisationName)$($projectName)/_releaseProgress?_a=release-pipeline-progress&releaseId=$($ReleaseId)"">Click Here</a> To View Release $($ReleaseVersion)</td>
                        </tr>
                    </table>
                </td>
            </tr>
            <tr><td>&nbsp;</td></tr>
            <tr style=""width: 100%; border: solid 2px rgba(103, 103, 103, 0.10); padding: 10px;"">
                <td style=""width: 100%; margin-bottom: 15px;"">
                    <div style=""position: relative; float: left; font-size: 13px; text-align: left; padding: 10px;"">
                        This notification was send on behalf of [Sebata.EMS]\EMS Deployment and Database.
                        <br /><br />
                        <span style=""color: #0078d4; font-weight: 400;"">Please do not reply to this message as it comes from an unattended mailbox.</span>
                        <br /><br />
                        <span style=""font-size: 11px; color: #000;"">Sent from Azure</span> <span style="" font-size: 11px; color: #0078d4; font-weight: bold;"">DevOps</span>
                    </div>
                </td>
            </tr>
        </table>
    </body>
    </html>"
    )

#EMAIL FUNCTION
Function SendMail([string]$smtpServer, [string]$smtpPort, [string]$smtpUser, [string]$smtpPass, [string]$smtpFrom, [string]$smtpTo, [string]$smtpBody, [string]$smtpHeader)
{
    $emailMessage = New-Object System.Net.Mail.MailMessage($smtpFrom, $smtpTo)
    $emailMessage.Subject = "$($smtpHeader)"
    $emailMessage.IsBodyHtml = $true #true or false depends
    $emailMessage.Body = "$($smtpBody)"
    $SMTPClient = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
    $SMTPClient.EnableSsl = $False
    $SMTPClient.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPass);
    $SMTPClient.Send($emailMessage);
    Write-Output "##[section] E-Mail notification send."
}

#FINALISE TASK
if ($buildValidate -eq "Error")
{
    if($MailSend)
    {
        SendMail $emailSmtpServer $emailSmtpServerPort $emailSmtpUser $emailSmtpPass "$($emailFrom)" $emailTo $Body $smtpSubject
    }

    if ($buildFailed = "Failed")
    {
        Write-Host "##[error] Builds for $($ReleaseVersion) have failed."
        Write-Output "##vso[task.complete result=Failed;]DONE"
    }
    else
    {
        Write-Host "##[Warning] Builds for $($ReleaseVersion) are still in progress."
    }


}
else
{
    Write-Host "##[section] All builds for release $($ReleaseVersion) completed successfully."
    Write-Output "##vso[task.complete result=Succeeded;]DONE"
}



