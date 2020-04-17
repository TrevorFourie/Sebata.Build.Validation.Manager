clear
# ------------------------------------------------------------------------ *
#                                                                          *
# BUILD VALIDATION TOOL                                                    *
# ---------------------                                                    *
# Author: Trevor Fourie                                                    *
# Date  : 16 April 2020                                                    *
# TAKES THE BUILDS OFF YOUR PIPELINE AND VALIDATES THEM FOR THE FOLLOWING  *
#                                                                          *
#    1. BUILDS ARE TAKEN FROM THE CORRECT BRANCH AS PER INPUT              *
#    2. THERE ARE NO BUILDS CURRENTLY IN PROGRESS                          *
#    3. LATEST BUILDS HAVE NOT FAILED                                      *
#                                                                          *
# ------------------------------------------------------------------------ *

#region TASK PARAMETERS
# ------------------------------------------------------------------------ #
[string]$organisationName           = Get-VstsInput -Name azOrgName -Require
[string]$projectName                = Get-VstsInput -Name azProjectName -Require
[string]$repositoryName             = Get-VstsInput -Name azRepoName -Require
[int]$MaxBuildsToCheckPerBuild      = Get-VstsInput -Name azBuildAttempts -Require
[string]$validateBranch             = Get-VstsInput -Name azBranchName -Require
[string]$branch                     = "refs/heads/$($validateBranch)";
[string]$buildURL                   = "https://dev.azure.com/$($organisationName)/"
[string]$releaseURL                 = "https://vsrm.dev.azure.com/$($organisationName)/"
[string]$ReleaseVersion             = $env:RELEASE_RELEASENAME
[string]$ReleaseDefinitionName      = $env:RELEASE_DEFINITIONNAME
[string]$RELEASE_ENVIRONMENTNAME    = $env:RELEASE_ENVIRONMENTNAME
[int]$releaseID                     = $env:RELEASE_RELEASEID;
[int]$definitionID                  = $env:RELEASE_DEFINITIONID;
[int]$TotalRec                      = 2;
[string]$RetRes                     = '$top';
[string]$RetResults                 = "$($RetRes)=$($TotalRec)";
[string]$checkManualBuilds          = Get-VstsInput -Name azCheckBuild
[bool]$checkManualBuilds			= if ($checkManualBuilds -eq "false"){0}else{1};
[string]$MailSend		            = Get-VstsInput -Name azSendMail
[bool]$MailSend			            = if ($MailSend -eq "false"){0}else{1};
#endregion

#region VALIDATE ALL FIELDS ARE POPULATED 
# ------------------------------------------------------------------------ #
Function ThrowError([string]$variable, [string]$errMessage)
{
    if ([System.String]::IsNullOrWhiteSpace($variable))
    { 
        Write-Host "##[error] $($errMessage)";
        Write-Output "##vso[task.complete result=Failed;]DONE"
    }
}
ThrowError $($organisationName) "No Organisation name was specified. Verify that the organisation name is correct and not empty."
ThrowError $($projectName) "No Project name was specified. Verify that the name of the project is correct and that the project exists on the '$($orgName)' Azure DevOps Server."
ThrowError $($repositoryName) "No Repository name was specified. Verify that the repository name is correct and exists on the '$($projectName)' project."
ThrowError $($validateBranch) "No branch name was specified. Verify that the branch name is correct and exists on the '$($repositoryName)' repository."
ThrowError $($MaxBuildsToCheckPerBuild) "No build attempts specified. Verify that at least 1 build attempt is made."
ThrowError $($validateBranch) "No branch name was specified. Verify that the branch name is correct and not empty."

if($checkManualBuilds)
{
    [string]$ValidateBuilds             = Get-VstsInput -Name azBuildDefId -Require
    ThrowError $($ValidateBuilds) "No builds have been specified. Verify that the builds are not empty and that the correct format was used. I.e Build1;Build2;Build3;."
}

#endregion

#region AUTHENTICATION FOR AZURE 
# ------------------------------------------------------------------------ #
$devOpsHeader = @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"}
#endregion

#region VALIDATE THAT THE ORGANISATION AND PROJECT DOES EXIST 
# ------------------------------------------------------------------------ #
Try 
{
    $repoURL  = "$($buildURL)$($projectName)/_apis/git/repositories?api-version=4.1"
    $repoData = Invoke-RestMethod -Uri $repoURL -Headers $devOpsHeader
} 
Catch 
{
    Write-Host "##[error] $($_.Exception.Message)" ;
    Write-Host "##[error] The project '$($projectName)' or Organisation '$($organisationName)' could not be found. Verify that the name of the project and organisation is correct and that the project exists on the '$($organisationName)' Azure DevOps Server." ;
    Write-Output "##vso[task.complete result=Failed;]DONE"
}
#endregion

#region VALIDATE THAT THE REPOSITORY DOES EXIST 
# ------------------------------------------------------------------------ #
if($repositoryName.ToLower() -ne $repoData.value.name.ToLower())
{
    Write-Host "##[error] The repository '$($repositoryName)' could not be found. Verify that the name of the repository is correct and that the repository exists on the '$($projectName)' project." ;
    Write-Output "##vso[task.complete result=Failed;]DONE"
}
#endregion

#region VALIDATE THAT THE BRANCH DOES EXIST 
# ------------------------------------------------------------------------ #
$branchValidateURL = "$($buildURL)$($projectName)/_apis/git/repositories/$($repositoryName)/refs?filter=heads/&filterContains=$($validateBranch)&api-version=5.1"
$valData = Invoke-RestMethod -Uri $branchValidateURL -Headers $devOpsHeader 
if ($valData.count -eq 0)
{
    Write-Host "##[Error] Branch '$($validateBranch -replace 'refs/heads/', '')' could not be found. Verify that the name of the branch name is correct and that the branch exists on the '$($repositoryName)' reporsitory." ;
    Write-Output "##vso[task.complete result=Failed;]DONE"
}
#endregion

#region API CONNECTION TO OBTAIN THE BUILDS FOR THE RELEASE 
# ------------------------------------------------------------------------ #
$deployurl = "$($releaseURL)$($projectName)/_apis/release/releases/$($releaseID)?api-version=5.1"
$deploy = Invoke-RestMethod -Uri $deployurl -Headers $devOpsHeader
#endregion

#region CREATE ARRAY FROM BUILD INPUT FIELDS TO USE IF MANUAL BUILD CHECKS ENABLED
# ------------------------------------------------------------------------ #
if($checkManualBuilds)
{
    $branchFields = $ValidateBuilds.Split(";");
    $branchFields = @($branchFields);
}
$global:branchError = 0;
$global:buildOutPut = "";
$global:BuildReturn = "";
$global:buildFailed = "";
$global:buildStatus = "";
#endregion

#region FUNCTION TO SEE THAT NO BUILD IS IN PROGRESS OR HAS FAILED 
# ------------------------------------------------------------------------ #
Function BuildDetails([string]$definitionsval, [string]$buildAttempts, [string]$TopReturn, [string]$branchNameBuild, [string]$validateBuildNumber)
{
    $buildBranchURL  = "$($buildURL)$($projectName)/_apis/build/builds?$($TopReturn)&definitions=$($definitionsval)&maxBuildsPerDefinition=$($buildAttempts)&queryOrder=queueTimeDescending&statusFilter=all&branchName=$($branchNameBuild)&api-version=5.1"
    $buildData = Invoke-RestMethod -Uri $buildBranchURL -Headers $devOpsHeader 

        foreach($build in $buildData.value)
        {
            # ------------------------------------------------------------------------ #
            # BUILD HAS FAILED                                                         #
            # ------------------------------------------------------------------------ #
            if ($build.result -eq "failed")
            {
                Write-Host "##[Error] Build Result    : Failed" ;
                Write-Host "##[Error] Build Name      : $($build.definition.name)" ;
                Write-Host "##[Error] Build Number    : $($build.buildNumber)"  ;
                Write-Host "##[Error] Build Status    : $($build.status)"  ;
                Write-Host "##[Error] Latest Build Has Failed" ;
                $global:BuildReturn = "<td style=""position: relative; float: left; width: auto; text-align: left;"">: $($build.buildNumber)</td><td style="" position: relative; float: left; width: 70px; text-align: center; color: red;"">Failed</td>"
                $global:buildOutPut += "<tr style=""width: 100%; padding-bottom: 5px;""><td style=""position: relative; float: left; width: auto; text-align: left;"">- $($build.definition.name)</td>$($BuildReturn)<td style=""position: relative; float: left; width: 80px; text-align: center;"">(<a target="" _blank"" href="" $($build._links.web.href)"">View Build</a>)</td></tr>";
                $global:buildFailed = "Failed";             
                $global:branchError++;
            }
            # ------------------------------------------------------------------------ #
            # BUILD IS IN PROGRESS                                                     #
            # ------------------------------------------------------------------------ #
            elseif ($build.status -eq "inProgress")
            {
                Write-Host "##[Warning] *** Release Is Currently In Progress ***";
                Write-Host "##[Warning] Build Result    : In Progress";
                Write-Host "##[Warning] Build Number    : $($build.buildNumber)" 
                $global:BuildReturn = "<td style=""position: relative; float: left; width: auto; text-align: left;"">: $($build.buildNumber)</td><td style="" position: relative; float: left; width: 70px; text-align: center; color: Orange;"">In Progress</td>"
                $global:buildOutPut += "<tr style=""width: 100%; padding-bottom: 5px;""><td style=""position: relative; float: left; width: auto; text-align: left;"">- $($build.definition.name)</td>$($BuildReturn)<td style=""position: relative; float: left; width: 80px; text-align: center;"">(<a target="" _blank"" href="" $($build._links.web.href)"">View Build</a>)</td></tr>";
                $global:buildStatus = "inProgress";             
                $global:branchError++; 
            }
        }
        Write-Host "------------------------------------------------------------------------------";
}
#endregion

#region FUNCTION TO SEE THAT THE BUILDS USED IN THE RELEASE MATCHES THE BRANCH USED IN THE INPUT FIELD 
# ---------------------------------------------------------------------------------------------------- #
Function CHECKBUILDS([string]$GetBuildId, [string]$validateBranch)
{

    $currentBranch = $buildshow.sourceBranch.Replace('refs/heads/','').Trim();
    $definitions = $buildshow.definition.id;
    Write-Host "Build Name    : $($buildshow.definition.name)"
    Write-Host "Build Version : $($buildshow.buildNumber)"
    Write-Host "Build Branch  : $($buildshow.sourceBranch.Replace('refs/heads/',''))"
    Write-Host "Build Result  : $($buildshow.result)"
    if($validateBranch.ToLower() -ne $currentBranch.ToLower())
    {
        Write-Host "##[Error] Build '$($buildshow.definition.name)' was not taken from branch '$($validateBranch)'" ;                       
        $global:branchError++;
    }
    # CALL FUNCTION TO SEE IF LATEST BUILDS PASSED AND ARE NOT IN PROGRESS
    BuildDetails $buildshow.definition.id $MaxBuildsToCheckPerBuild $RetResults $branch $buildshow.buildNumber;
}
#endregion

#region RUN VALIDATION 
# ------------------------------------------------------------------------ #
Write-Host "Validating builds from branch '$($validateBranch)'";
Write-Host "------------------------------------------------------------------------------";
foreach($build in $deploy)
{
    $BuildIDS = $build.artifacts.definitionReference.buildUri.id -replace "vstfs:///Build/Build/", ""
    $BuildIDS = $BuildIDS.split(" ");
    [int]$countBuilds = $BuildIDS.Count;
    for($i = 0; $i -lt $countBuilds; $i++)
    {
        $currentBuild = $BuildIDS[$i];
        $buildValurl = "$($buildURL)$($projectName)/_apis/build/builds/$($currentBuild)?api-version=5.1"
        $buildshow = Invoke-RestMethod -Uri $buildValurl -Headers $devOpsHeader
        if($checkManualBuilds)
        {
            if ($branchFields -contains $buildshow.definition.name)
            {
                CHECKBUILDS $BuildIDS[$i] $validateBranch
            }
            else
            {
                Write-Host "##[Warning] Build Name    : $($buildshow.definition.name)"
                Write-Host "##[Warning] Build Version : $($buildshow.buildNumber)"
                Write-Host "##[Warning] Build not being validated as it was not found in the list of builds to validate";
                Write-Host "------------------------------------------------------------------------------"
            }
        }
        else
        {
            CHECKBUILDS $BuildIDS[$i] $validateBranch
        }
    }
}
#endregion

#region SEND E-MAIL IF OPTION SELECTED AND VALIDATION HAS FAILED 
# ------------------------------------------------------------------------ #
if($MailSend)
{
	# VALIDATE ALL FIELDS ARE POPULATED WHEN MAIL SELECTED #
    # **************************************************** #
	$emailSmtpServer = Get-VstsInput -Name azSmtpServer -Require
	$emailSmtpServerPort = Get-VstsInput -Name azSmtpPort -Require
	$emailSmtpUser = Get-VstsInput -Name azSmtpUser -Require
	$emailSmtpPass = Get-VstsInput -Name azSmtpPass -Require
	$emailFrom = "Azure Devops <$($emailSmtpUser)>" 
	$emailToInput = Get-VstsInput -Name azSmtpTo -Require
	$emailTo = $emailToInput -replace ";", "`,"

    ThrowError $($emailSmtpServer) "No SMTP Mail Server Specified."
    ThrowError $($emailSmtpServerPort) "No SMTP Mail Server Port Specified."
    ThrowError $($emailSmtpUser) "No SMTP Mail Server User Name Specified."
    ThrowError $($emailSmtpPass) "No SMTP Mail Server User Password Specified."
    ThrowError $($emailToInput) "No E-Mails address To someone specified."
    
    # EMAIL SUBJECT #
    # ************* #
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
                                <td style=""position: relative; float: left; text-align: left;"">: $($validateBranch)</td>
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
        Write-Output "##[warning] Error notification send."
    }
}
#endregion

#region FINALISE TASK 
# ------------------------------------------------------------------------ #
if ($global:branchError -gt 0)
{
    if ($global:buildFailed -eq "Failed")
    {
        if($MailSend) { SendMail $emailSmtpServer $emailSmtpServerPort $emailSmtpUser $emailSmtpPass "$($emailFrom)" $emailTo $Body $smtpSubject }
        Write-Host "##[Error] Branch Validation Failed for '$($ReleaseVersion)' with $($global:branchError) Error(s)";
        Write-Host "##vso[task.complete result=Failed;]DONE";
    }
    elseif ($global:buildStatus -eq "inProgress")
    {
        if($MailSend) { SendMail $emailSmtpServer $emailSmtpServerPort $emailSmtpUser $emailSmtpPass "$($emailFrom)" $emailTo $Body $smtpSubject }
        Write-Host "##[Warning] Builds for $($ReleaseVersion) are still in progress.";
        Write-Output "##vso[task.complete result=SucceededWithIssues;]DONE";
    }
}
else
{
    Write-Host "##[section] All builds for release $($ReleaseVersion) completed successfully.";
    Write-Output "##vso[task.complete result=Succeeded;]DONE";
}
#endregion