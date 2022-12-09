
#Region functions
function Get-MMDAADApp {
	# Checks to see if there is an existing MMD AAD Application in your environment and returns the correct ID for you.
	$result = Get-MgApplication | Where-Object { $_.requiredresourceaccess.ResourceAppId -like "*c9d36ed4-91b3-4c87-b8d7-68d92826c96c*" }
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
	# MSAL.PS to create MSAL token for authentication
	if ((Get-Module MSAL.PS -ListAvailable)) {
		Import-Module MSAL.PS -Force
	}
	else {
		Install-Module MSAL.PS -Scope CurrentUser
		Import-Module MSAL.PS -Force
	}
	# AzureAD to create the MMD Applicaiton
	if ((Get-Module Microsoft.graph -ListAvailable)) {
		Import-Module Microsoft.graph.Applications
		Import-Module Microsoft.Graph.Authentication
	}
	else {
		Install-Module Microsoft.graph -Scope CurrentUser
		Import-Module Microsoft.graph.Applications
		Import-Module Microsoft.Graph.Authentication
	}
}

function new-MMDAADApp {
	Connect-MgGraph -Scopes "Application.ReadWrite.All","Application.Read.All"
	$tenant = Get-MgContext
	# Set the name of the AAD application
	$displayname = "MMD Application"
	$Access = @(
		@{ ResourceAppId = "00000003-0000-0000-c000-000000000000"; ResourceAccess = @(
				# Permission: offline_access
				@{ Id = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182"; Type = "Scope" },
				# Permission: User.Read
				@{ Id = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"; Type = "Scope" },
				# Permission: openid
				@{ Id = "37f7f235-527c-4136-accd-4a02d197296e"; Type = "Scope" }
			)
		}
		@{ ResourceAppId = "c9d36ed4-91b3-4c87-b8d7-68d92826c96c"; ResourceAccess = @(
				# Permission: MWaaSDevice.Read
				@{ Id = "f1b8ecc9-3ae0-410c-b53b-23d0827c5210"; Type = "Scope" },
				# Permission: MmdDeviceEnroller.ReadWrite
				@{ Id = "318a1541-71b6-4e1e-ab46-874e6095cdfa"; Type = "Role" },
				# Permission: MmdAppTester.ReadWrite
				@{ Id = "1dcf702a-7efe-47e6-961f-68634c4a4ecd"; Type = "Role" },
				# Permission: MmdSupport.ReadWrite
				@{ Id = "50d736c0-5102-4a54-b3f6-95509aae4293"; Type = "Role" }
			)
		}
	)
	$publicclient = New-Object -TypeName "Microsoft.Graph.PowerShell.Models.MicrosoftGraphPublicClientApplication"
	$publicclient.RedirectUris = "https://login.microsoftonline.com/common/oauth2/nativeclient"
	# Creating the AAD Application
	#$scopes = "MmdAppTester.ReadWrite","MmdDeviceEnroller.ReadWrite","MmdSupport.ReadWrite","MWaaSDevice.read","openid","offline_access","User.read"
	$mmdApplication = New-MgApplication -DisplayName $displayname -RequiredResourceAccess $access -PublicClient $publicclient -SignInAudience "AzureADMyOrg"
	Start-Sleep -Seconds 45
	# Prompting to consent to the use of the API's
	Get-MsalToken -ClientId $MMDApplication.appId -TenantId $tenant.TenantID -Scopes "openid offline_access https://mwaas-services-customerapi-prod.azurewebsites.net/.default" -Interactive -Prompt Consent | Out-Null
	# Returns the App ID
	return $MMDApplication
}

#EndRegion

#Region auth

Initialize-MMDENV
Connect-MgGraph -Scopes "Application.Read.All" | Out-Null
$tenant = Get-MgContext
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
