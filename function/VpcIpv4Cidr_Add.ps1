<#
.SYNOPSIS
This cmdlet adds a secondary IPv4 CIDR block to a VPC.
You can specify the VPC(s) using either the -VpcName or -VpcId Parameter.

.PARAMETER VpcId
The -VpcId Parameter specifies the VPC ID.
You can also pass in an array of VPC IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER VpcName
The -VpcName Parameter specifies the VPC's Name.
You can use glob wildcards to match multiple VPCs.
You can also pass in an array of Names.
See example 2.

.PARAMETER Ipv4Cidr
The -Ipv4Cidr Parameter specifies the secondary IPv4 CIDR block to add to the VPC.

.EXAMPLE
Add-VpcIpv4Cidr vpc-1234567890abcdef0 10.255.0.0/16

This example adds an IPv4 CIDR block "10.255.0.0/16" to the VPC vpc-1234567890abcdef0.

.EXAMPLE
Add-VpcIpv4Cidr -VpcName example-* 10.255.0.0/16

This example adds an IPv4 CIDR block "10.255.0.0/16" to all VPCs with Name that starts with "example-".
#>
function Add-VpcIpv4Cidr
{
    [Alias('vpc_ipv4_add')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string[]]
        $VpcName,

        [Parameter(ParameterSetName = 'VpcId', Mandatory)]
        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 1)]
        [ValidatePattern(
            '^(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}' + # 255.255.255.
            '([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' +         # 255
            '\/([0-9]|[1-2][0-9]|3[0-2])$',                                # /32
            ErrorMessage = 'Invalid Ipv4Cidr.'
        )]
        [string]
        $Ipv4Cidr
    )

    BEGIN
    {
        # For easy pickup.
        $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
        $_param_set   = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_vpc_id   = $VpcId
        $_vpc_name = $VpcName
        $_cidr     = $Ipv4Cidr

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the list of VPC first.
        try {
            $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no VPC matched the filter value, exit early.
        if (-not $_vpc_list) {

            Write-Error "No VPC was found for '$_filter_value'."
            return
        }

        # Loop through each VPC to perform the CIDR addition.
        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for this VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, "Add new IPv4 CIDR block $_cidr"))
            {
                try {
                    # Call the API to add the IPv4 CIDR to this VPC.
                    $_result = Register-EC2VpcCidrBlock -VpcId $_.VpcId -CidrBlock $_cidr -Verbose:$false

                    # Wait for the association to complete.
                    Write-Message -Progress $_cmdlet_name "|- Waiting for association to complete."

                    $_counter = 0
                    do {
                        Start-Sleep 1; $_counter++

                        $_assoc_set = Get-EC2Vpc -Verbose:$false -Filter @{
                            Name   = 'cidr-block-association.association-id'
                            Values = $_result.CidrBlockAssociation.AssociationId
                        } |
                        Select-Object -ExpandProperty CidrBlockAssociationSet |
                        Where-Object AssociationId -eq $_result.CidrBlockAssociation.AssociationId

                        $_state = $_assoc_set.CidrBlockState.State

                    } while ($_state -ne 'associated' -and $_counter -le 3)

                    # Return the result to the caller.
                    Write-Message -Output "|- State: $_state."
                }
                catch {
                    # Remove caught exception emitted into $Error list.
                    Pop-ErrorRecord $_

                    # Report error as non-terminating.
                    $PSCmdlet.WriteError($_)
                }
            }
        }
    }
}