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

    # MFA
    'mfa',

    # Prefix List
    'pl_resolve', 'pl_read', 'pl_write',

    # VPC BPA Exclusion
    'vpc_bpa_excl_show', 'vpc_bpa_excl_add', 'vpc_bpa_excl_edit', 'vpc_bpa_excl_rm',

    # VPC
    'vpc_show', 'vpc_add', 'vpc_rn', 'vpc_rm',

    # VPC CIDR
    'vpc_ipv4_add', 'vpc_ipv4_rm',
    'vpc_ipv6_add', 'vpc_ipv6_rm',

    # VPC CIDR Map
    'vpc_cidrmap_show',

    # VPC Attribute
    'vpc_dnsres_en',  'vpc_dnsres_dis',
    'vpc_dnshost_en', 'vpc_dnshost_dis',
    'vpc_nau_en',     'vpc_nau_dis',

    # VPC Peering
    'pcx_show', 'pcx_add', 'pcx_rn', 'pcx_rm',
    'pcx_accept', 'pcx_reject',

    # VPC Peering Attributes
    'pcx_dns_en', 'pcx_dns_dis',

    # Internet Gateway
    'igw_show', 'igw_add', 'igw_rn', 'igw_rm', 'igw_mount', 'igw_umount',

    # Subnet
    'subnet_show', 'subnet_add', 'subnet_cp', 'subnet_rn', 'subnet_rm',

    # Subnet CIDR
    'subnet_ipv6_add', 'subnet_ipv6_rm',

    # Subnet Attribute
    'subnet_aaaa_en', 'subnet_aaaa_dis',
    'subnet_a_en', 'subnet_a_dis',
    'subnet_aip_en', 'subnet_aip_dis',
    'subnet_aip6_en', 'subnet_aip6_dis',
    'subnet_dns64_en', 'subnet_dns64_dis',
    'subnet_host',

    # Route Table
    'rt_show', 'rt_add', 'rt_rn', 'rt_rm',

    # Default Route Table
    'rt_default', 'rt_default?', 'rt_default_clear',

    # Route Table Association
    'rt_assoc_add', 'rt_assoc_rm',

    # Route Entry
    'route_show', 'route_find', 'route_add', 'route_rm',

    # Network ACL
    'nacl_show', 'nacl_add', 'nacl_rn', 'nacl_rm',

    # Security Group
    'sg_show', 'sg_add', 'sg_clear', 'sg_cp',
    'sg_rn', 'sg_rm',

    # Default Security Group
    'sg_default', 'sg_default?',

    # Security Group Rule
    'sgr_show',

    # Lambda
    'func_show',

    # CloudFormation
    'stack_show', 'stackinstance_show',
    'iac_scan_brief', 'iac_scan_detail',

    # Identity Center
    'sso_assign_show', 'sso_uperm_show',

    # AWS Organization
    'org_tree'
)

# Variables
Export-ModuleMember -Variable 'ResourceStringPreference'
Export-ModuleMember -Variable 'DefaultRouteTable'