#using namespace Worker369.AWS

$model_files        = "$PSScriptRoot/model/*.ps1"
$function_files     = "$PSScriptRoot/function/*.ps1"
$autocomplete_files = "$PSScriptRoot/autocomplete/*.ps1"

# Model
Get-Item $model_files | ForEach-Object {. $_.FullName}

# Functions = AWS Shell
Get-Item $function_files | ForEach-Object {. $_.FullName}

# Autocomplete
Get-Item $autocomplete_files | ForEach-Object {. $_.FullName}

# Aliases
Export-ModuleMember -Alias @(

    # ---------------------------------------------------------------------------------------------------------------- #
    # AWS Organization
    # ---------------------------------------------------------------------------------------------------------------- #
    'org_tree',                         # Show-OrgTree

    # ---------------------------------------------------------------------------------------------------------------- #
    # CloudFormation
    # ---------------------------------------------------------------------------------------------------------------- #
    'stack_show',                       # Show-Stack
    'stack_drift_show',                 # Show-StackDrift
    'stack_instance_show',              # Show-StackInstance
    'stack_resource_show',              # Show-StackResource
    'iac_scan_brief',                   # Show-IacSacnBrief
    'iac_scan_detail',                  # Show-IacScanDetail

    # ---------------------------------------------------------------------------------------------------------------- #
    # CloudWatch Alarms
    # ---------------------------------------------------------------------------------------------------------------- #
    'alarm_ec2_cpu',                    # New-Ec2CpuAlarm
    'alarm_ec2_status',                 # New-Ec2StatusAlarm

    # ---------------------------------------------------------------------------------------------------------------- #
    # EC2
    # ---------------------------------------------------------------------------------------------------------------- #
    'ec2_show',                         # Show-Ec2
    'ec2_console',                      # Get-Ec2SystemLog

    # ---------------------------------------------------------------------------------------------------------------- #
    # ENI
    # ---------------------------------------------------------------------------------------------------------------- #
    'eni_show',                         # Show-NetworkInterface

    # ---------------------------------------------------------------------------------------------------------------- #
    # IAM
    # ---------------------------------------------------------------------------------------------------------------- #
    'iam_role_show',                    # Show-IamRole
    'iam_role_trust_show',              # Show-IamRoleTrustPolicy
    'iam_policy_find',                  # Find-IamPolicy
    'iam_policy_read',                  # Read-IamPolicyDocument
    'iam_policy_cat',                   # Show-IamPolicyContent

    # ---------------------------------------------------------------------------------------------------------------- #
    # Identity Center
    # ---------------------------------------------------------------------------------------------------------------- #
    'sso_assign_show',                  # Show-SsoAssignment
    'sso_uperm_show',                   # Show-SsoUserPermission

    # ---------------------------------------------------------------------------------------------------------------- #
    # Internet Gateway
    # ---------------------------------------------------------------------------------------------------------------- #
    'igw_show',                         # Show-InternetGateway
    'igw_add',                          # New-InternetGateway
    'igw_rn',                           # Rename-InternetGateway
    'igw_rm',                           # Remove-InternetGateway
    'igw_mount',                        # Mount-InternetGateway
    'igw_umount',                       # Dismount-InternetGateway

    # ---------------------------------------------------------------------------------------------------------------- #
    # Lambda
    # ---------------------------------------------------------------------------------------------------------------- #
    'func_show',                        # Show-Lambda

    # ---------------------------------------------------------------------------------------------------------------- #
    # KMS
    # ---------------------------------------------------------------------------------------------------------------- #
    'kms_show',                         # Show-Kms

    # ---------------------------------------------------------------------------------------------------------------- #
    # Managed Prefix List
    # ---------------------------------------------------------------------------------------------------------------- #
    'pl_resolve', 'pl_read',            # Resolve-PrefixList
    'pl_write',                         # Write-PrefixList

    # ---------------------------------------------------------------------------------------------------------------- #
    # MFA
    # ---------------------------------------------------------------------------------------------------------------- #
    'mfa',                              # Write-MfaProfile

    # ---------------------------------------------------------------------------------------------------------------- #
    # Network ACL
    # ---------------------------------------------------------------------------------------------------------------- #
    'nacl_show',                        # Show-NetworkAcl
    'nacl_add',                         # New-NetworkAcl
    'nacl_rn',                          # Rename-NetworkAcl
    'nacl_rm',                          # Remove-NetworkAcl

    # ---------------------------------------------------------------------------------------------------------------- #
    # Route 53
    # ---------------------------------------------------------------------------------------------------------------- #
    'dns_show',                         # Show-Route53Dns

    # ---------------------------------------------------------------------------------------------------------------- #
    # Route Table
    # ---------------------------------------------------------------------------------------------------------------- #
    'rt_show',                          # Show-RouteTable
    'rt_add',                           # New-RouteTable
    'rt_rn',                            # Rename-RouteTable
    'rt_rm',                            # Remove-RouteTable
    'rt_default',                       # Set-DefaultRouteTable
    'rt_default?',                      # Get-DefaultRouteTable
    'rt_default_clear',                 # Clear-DefaultRouteTable
    'rt_assoc_add',                     # New-RouteTableAssociation
    'rt_assoc_rm',                      # Remove-RouteTableAssociation
    'route_show',                       # Show-Route
    'route_find',                       # Find-Route
    'route_add',                        # Add-Route
    'route_rm',                         # Remove-Route

    # ---------------------------------------------------------------------------------------------------------------- #
    # S3
    # ---------------------------------------------------------------------------------------------------------------- #
    's3_ls',                            # Show-S3Folder
    's3_cat',                           # Show-S3FileContent
    's3_ver',                           # Show-S3FileVersion
    's3_show',                          # Show-S3Bucket
    's3_policy_show',                   # Show-S3Policy
    's3_get',                           # Get-S3File
    's3_clear',                         # Clear-S3Bucket
    's3_ver_en',                        # Enable-S3Versioning
    's3_ver_dis',                       # Disable-S3Versioning
    's3_bkey_en',                       # Enable-S3BucketKey
    's3_bkey_dis',                      # Disable-S3BucketKey
    's3_encrypt',                       # Set-S3Encryption
    's3_blkencrypt',                    # Set-S3BlockedEncryption
    's3_blkencrypt_clear',              # Clear-S3BlockedEncryption

    # ---------------------------------------------------------------------------------------------------------------- #
    # Security Group
    # ---------------------------------------------------------------------------------------------------------------- #
    'sg_show',                          # Show-SecurityGroup
    'sg_add',                           # New-SecurityGroup
    'sg_clear',                         # Clear-SeurityGroup
    'sg_cp',                            # Copy-SecurityGroup
    'sg_rn',                            # Rename-SecurityGroup
    'sg_rm',                            # Remove-SecurityGroup
    'sg_default',                       # Set-DefaultSecurityGroup
    'sg_default?',                      # Get-DefaultSecurityGroup
    'sgr_show',                         # Show-SecuriryGroupRule

    # ---------------------------------------------------------------------------------------------------------------- #
    # SES
    # ---------------------------------------------------------------------------------------------------------------- #
    'ses_send',                         # Sene-SesEmailMessage

    # ---------------------------------------------------------------------------------------------------------------- #
    # SSM
    # ---------------------------------------------------------------------------------------------------------------- #
    'fleet_show',                       # Show-Fleet

    # ---------------------------------------------------------------------------------------------------------------- #
    # Subnet
    # ---------------------------------------------------------------------------------------------------------------- #
    'subnet_show',                      # Show-Subnet
    'subnet_add',                       # New-Subnet
    'subnet_cp',                        # Copy-Subnet
    'subnet_rn',                        # Rename-Subnet
    'subnet_rm',                        # Remove-Subnet
    'subnet_ipv6_add',                  # Add-SubnetIpv6Cidr
    'subnet_ipv6_rm',                   # Remove-SubnetIpv6Cidr
    'subnet_aaaa_en',                   # Enable-SubnetAAAARecord
    'subnet_aaaa_dis',                  # Disable-SubnetAAAARecord
    'subnet_a_en',                      # Enable-SubnetARecord
    'subnet_a_dis',                     # Disable-SubnetARecord
    'subnet_aip_en',                    # Enable-SubnetAutoAssignPublicIP
    'subnet_aip_dis',                   # Disable-SubnetAutoAssignPublicIP
    'subnet_aip6_en',                   # Enable-SubnetAutoAssignIPv6
    'subnet_aip6_dis',                  # Disable-SubnetAutoAssignIPv6
    'subnet_dns64_en',                  # Enable-SubnetDns64
    'subnet_dns64_dis',                 # Disable-SubnetDns64
    'subnet_host',                      # Set-SubnetHostnameType

    # ---------------------------------------------------------------------------------------------------------------- #
    # Transit Gateway
    # ---------------------------------------------------------------------------------------------------------------- #
    'tgw_rt_show',                      # Show-TransitGatewayRouteTable
    'tgw_route_show',                   # Show-TransitGatewayRoute

    # ---------------------------------------------------------------------------------------------------------------- #
    # VPC
    # ---------------------------------------------------------------------------------------------------------------- #
    'vpc_show',                         # Show-Vpc
    'vpc_add',                          # New-Vpc
    'vpc_rn',                           # Rename-Vpc
    'vpc_rm',                           # Remove-Vpc
    'vpc_ipv4_add',                     # Add-VpcIpv4Cidr
    'vpc_ipv4_rm',                      # Remove-VpcIpv4Cidr
    'vpc_ipv6_add',                     # Add-VpcIpv6Cidr
    'vpc_ipv6_rm',                      # Remove-VpcIpv6Cidr
    'vpc_cidrmap_show',                 # Show-VpcCidrMap
    'vpc_dnsres_en',                    # Enable-VpcDnsResolution
    'vpc_dnsres_dis',                   # Disable-VpcDnsResolution
    'vpc_dnshost_en',                   # Enable-VpcDnsHostnames
    'vpc_dnshost_dis',                  # Disable-Vpc-DnsHostnames
    'vpc_nau_en',                       # Enable-VpcNauMetrics
    'vpc_nau_dis',                      # Disable-VpcNauMetrics
    'vpc_bpa_excl_show',                # Show-VpcBpaExclusion
    'vpc_bpa_excl_add',                 # New-VpcBpaExclusion
    'vpc_bpa_excl_edit',                # Edit-VpcBpaExclusion
    'vpc_bpa_excl_rm',                  # Remove-VpcBpaExclusion

    # ---------------------------------------------------------------------------------------------------------------- #
    # VPC Peering
    # ---------------------------------------------------------------------------------------------------------------- #
    'pcx_show',                         # Show-VpcPeering
    'pcx_add',                          # New-VpcPeering
    'pcx_rn',                           # Rename-VpcPeering
    'pcx_rm',                           # Remove-VpcPeering
    'pcx_accept',                       # Approve-VpcPeering
    'pcx_reject',                       # Deny-VpcPeering
    'pcx_dns_en',                       # Enable-VpcPeeringDns
    'pcx_dns_dis'                       # Disable-VpcPeeringDns
)

# Id | IdAndName | Name
Export-ModuleMember -Variable 'ResourceStringPreference'

# Default Route Table To Work On When Using route_show
Export-ModuleMember -Variable 'DefaultRouteTable'

# On/Off HTML Output
[bool]$EnableHtmlOutput = $false
$EnableHtmlOutput | Out-Null
Export-ModuleMember -Variable 'EnableHtmlOutput'

# Caches For IAM Policy ARNs
[string[]]$IamPolicyCache_Local = @()
[string[]]$IamPolicyCache_AWS   = @()
$IamPolicyCache_Local | Out-Null
$IamPolicyCache_AWS   | Out-Null
Export-ModuleMember -Variable 'IamPolicyCache_Local'
Export-ModuleMember -Variable 'IamPolicyCache_AWS'