<!DOCTYPE html>
 <html xmlns="http://www.w3.org/1999/xhtml">
 <head>
 </head>
 <body>
     <h1>Sebata Build Validation Manager</h1>
     <h2>Introduction</h2>
     <p>
         The Sebata Build Validation Manager allows you to validate your builds during the release process. It takes the builds from the release and validates them on the following conditions:
         <ul>
             <li>Is the build coming from the correct branch (https://developercommunity.visualstudio.com/content/problem/822000/incorrect-build-used-when-filter-by-latest-from-br.html)</li>
             <li>Are there any builds in progress for the Build Artifacts used in this release</li>
             <li>Has the latest build failed for any of the Build Artifacts used in this release</li>
         </ul>
         <br />
         It looks for any builds in the release, checks that it's using the correct branch and if any of the builds are in progress or failed and allows you to send out an e-mail to inform certain people if a release has failed.
         <br />
         If a builds has failed, it will fail the release pipeline, but for In progress builds it will continue and show the release as partially succeeded.
         <br />
         <br />
         If your release pipelines has more than one stage you will need select the option in the pre-deployment conditions of the stage(s) following the partially successful stage to continue with the release.
     </p>
     <p>
         You can validate multiple builds or a single build per project, repository and branch. You can also select how many builds you want to return for each of the builds. If you do not select to use your own build inputs, it will validate all the builds in the release against the branch you have entered to validate against.
         <br />
         If however you select to manually validate the builds (in cases where different builds come from different branches) and you do not select a build, it will give you a warning if a build has not been validated.
     </p>
     <p>
         <b>You will require an SMTP server to send e-mail notifications, should you wish to notify anybody of a failure.</b>. It's also recommended to save your password in a variable and set it as a 'secret' and calling the variable.
     </p>
     <p>
         <img src="https://trevorfourie.gallerycdn.vsassets.io/extensions/trevorfourie/294d2e8e-96f8-4be4-982b-077c7cbc4ca4/0.1.4/1587130728485/Microsoft.VisualStudio.Services.Screenshots.4" />
     </p>
     <h2>Options that you can select</h2>
     <p>
         <ul>
             <li>Organisation Name</li>
             <li>Project Name</li>
             <li>Repository Name</li>
             <li>Branch Name</li>
             <li>Build Attempts</li>
             <li>Select to Use Manual Builds</li>
             <li>Single or Multiple Builds</li>
             <li>Select to send an E-mail Notification</li>
             <li>SMTP Server Name / IP</li>
             <li>SMTP Server Port</li>
             <li>SMTP Server Username Login</li>
             <li>SMTP Server User Password</li>
             <li>Option to mail a single or multiple users</li>
         </ul>
     </p>
     <h2>Options - Builds</h2>
     <p>
         <img src="https://trevorfourie.gallerycdn.vsassets.io/extensions/trevorfourie/294d2e8e-96f8-4be4-982b-077c7cbc4ca4/0.1.4/1587130728485/Microsoft.VisualStudio.Services.Screenshots.1" />
     </p>
     <h2>Options - E-Mail</h2>
     <p>
         <img src="https://trevorfourie.gallerycdn.vsassets.io/extensions/trevorfourie/294d2e8e-96f8-4be4-982b-077c7cbc4ca4/0.1.4/1587130728485/Microsoft.VisualStudio.Services.Screenshots.2" />
     </p>
     <h2>Parially Successful - Continue with release</h2>
     <p>
         <img src="https://trevorfourie.gallerycdn.vsassets.io/extensions/trevorfourie/294d2e8e-96f8-4be4-982b-077c7cbc4ca4/0.1.4/1587130728485/Microsoft.VisualStudio.Services.Screenshots.5" />
     </p>
     <h2>Permissions</h2>
     <p>
         Your Pipeline should have access to the OAuth Token.
     </p>
     <p>
         <img src="https://trevorfourie.gallerycdn.vsassets.io/extensions/trevorfourie/294d2e8e-96f8-4be4-982b-077c7cbc4ca4/0.1.4/1587130728485/Microsoft.VisualStudio.Services.Screenshots.3" />
     </p>
     <h2>Update</h2>
     <p>
         In essence to quote Travis (The boss) : "ok so it valet's the car, then goois a VIP invite to fix the kakstation?"
         <br />
         <br />
         17 April 2020
         <br />
         - Version 0.1.6 : Release Version (Beta)
     </p>
 </body>
 </html>
