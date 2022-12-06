
#Region functions
function Get-MMDAADApp {
	# Checks to see if there is an existing MMD AAD Application in your environment and returns the correct ID for you.
	$result = Get-AzureADApplication | Where-Object { $_.requiredresourceaccess -like "*c9d36ed4-91b3-4c87-b8d7-68d92826c96c*" }
	if ($result.count -eq 1) {
		$result
	}
	elseif ($result.count -gt 1) {
		$result | Out-GridView -Passthru
	}
	else {
		new-MMDAADApp
	}
}

function Get-MMDAuthToken {
	param(
		# Obtain MMD App ID from the Get-MMDAADApp command
		[Parameter(Mandatory = $true)]
		[string]$MMDAppID,
		# This is the AAD TenantID
		[Parameter(Mandatory = $true)]
		[string]$tenantID,
		[Parameter(Mandatory = $false)]
		[securestring]$clientsecret
	)
	if ($PSBoundParameters.ContainsKey('clientsecret')) {
		Get-MsalToken -ClientId $MMDAppID -TenantId $tenantID -Scopes "openid offline_access https://mwaas-services-customerapi-prod.azurewebsites.net/.default" -ClientSecret $clientsecret
	}
	else {
		Get-MsalToken -ClientId $MMDAppID -TenantId $tenantID -Scopes "openid offline_access https://mwaas-services-customerapi-prod.azurewebsites.net/.default"
	}
}

function Initialize-MMDENV {
	# importing the required helper Modules.
	# AzureAD to create the MMD Applicaiton
	if ((Get-Module AzureAD -ListAvailable)) {
		Import-Module AzureAD
	}
	else {
		Install-Module AzureAD -Scope CurrentUser
		Import-Module AzureAD
	}
	# MSAL.PS to create MSAL token for authentication
	if ((Get-Module MSAL.PS -ListAvailable)) {
		Import-Module MSAL.PS
	}
	else {
		Install-Module MSAL.PS -Scope CurrentUser
		Import-Module MSAL.PS
	}
}

function new-MMDAADApp {
	[CmdletBinding(SupportsShouldProcess = $true)]
	param()
	Connect-AzureAD | Out-Null
	$tenant = Get-AzureADTenantDetail
	# Set the name of the AAD application
	$displayname = "MMD Application"
	$access = @()
	$reqAAD = New-Object -TypeName "Microsoft.Open.MSGraph.Model.RequiredResourceAccess"
	# Adds the "Modern Workplace Customer APIs" permissions to the new AAD Application
	$reqAAD.ResourceAppId = "c9d36ed4-91b3-4c87-b8d7-68d92826c96c"
	# Permission: MWaaSDevice.Read
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "f1b8ecc9-3ae0-410c-b53b-23d0827c5210","Scope"
	# Permission: MmdDeviceEnroller.ReadWrite
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "318a1541-71b6-4e1e-ab46-874e6095cdfa","Role"
	# Permission: MmdAppTester.ReadWrite
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "1dcf702a-7efe-47e6-961f-68634c4a4ecd","Role"
	# Permission: MmdSupport.ReadWrite
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "50d736c0-5102-4a54-b3f6-95509aae4293","Role"
	$access += $reqAAD
	$reqAAD = New-Object -TypeName "Microsoft.Open.MSGraph.Model.RequiredResourceAccess"
	# Adds the "GraphAggregatorService" permissions to the new AAD Application
	$reqAAD.ResourceAppId = "00000003-0000-0000-c000-000000000000"
	# Permission: offline_access
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "7427e0e9-2fba-42fe-b0c0-848c9e6a8182","Scope"
	# Permission: User.Read
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "e1fe6dd8-ba31-4d61-89e7-88639da4683d","Scope"
	# Permission: openid
	$reqAAD.ResourceAccess += New-Object -TypeName "Microsoft.Open.MSGraph.Model.ResourceAccess" -ArgumentList "37f7f235-527c-4136-accd-4a02d197296e","Scope"
	$access += $reqAAD
	$publicclient = New-Object -TypeName "Microsoft.Open.MSGraph.Model.PublicClientApplication"
	$publicclient.RedirectUris = "https://login.microsoftonline.com/common/oauth2/nativeclient"
	# Creating the AAD Application
	$MMDApplication = New-AzureADMSApplication -DisplayName $displayname -RequiredResourceAccess $access -PublicClient $publicclient -SignInAudience "AzureADMyOrg"
	# Need to pause while the AAD Application is created before we consent to the use of the APIs
	Start-Sleep -Seconds 45
	# Prompting to consent to the use of the API's
	Get-MsalToken -ClientId $MMDApplication.appId -TenantId $tenant.ObjectId -Scopes "openid offline_access https://mwaas-services-customerapi-prod.azurewebsites.net/.default" -Interactive -Prompt Consent | Out-Null
	# Returns the MSAL token to authenticate
	return Get-MsalToken -ClientId $MMDApplication.appId -TenantId $tenant.ObjectId -Scopes "openid offline_access https://mwaas-services-customerapi-prod.azurewebsites.net/.default"
}

#EndRegion

#Region auth

Initialize-MMDENV
$tenant = Connect-AzureAD
$tenantid = $tenant.TenantID
$MMDApp = Get-MMDAADApp
$MMDAppID = $MMDApp.appId
$mmdtoken = (Get-MMDAuthToken -TenantId $tenantid -MMDAppID $MMDAppID).CreateAuthorizationHeader()

#EndRegion

#Region Sample

function Get-MMDDeviceList {
	param(
		[Parameter(Mandatory = $true,
			HelpMessage = "AAD Tenant ID")]
		$tenantID,
		[Parameter(Mandatory = $true,
			HelpMessage = "MMD Authentication Token retrieved from Get-MMDAuthToken")]
		$MMDtoken
	)
	$uri = "https://mmdls.microsoft.com/support/odata/v1/tenants/$tenantID/devices"
	Invoke-RestMethod -Method Get -UseBasicParsing -Uri $uri -Headers @{ Authorization = $mmdtoken } -ContentType "application/json"
}

#EndRegion
Get-MMDDeviceList -TenantId $tenantID -MMDtoken $MMDtoken
