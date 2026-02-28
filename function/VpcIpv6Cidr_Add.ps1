<#
.SYNOPSIS
This cmdlet adds an Amazon-Provided IPv6 CIDR block to a VPC.
You can specify the VPC(s) using either the -Name or -VpcId Parameter.

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

.EXAMPLE
Add-VpcIpv6Cidr vpc-1234567890abcdef0

This example adds an Amazon-Provided IPv6 IPv6 CIDR block to the VPC vpc-1234567890abcdef0.

.EXAMPLE
Add-VpcIpv6Cidr -VpcName example-*

This example adds an Amazon-Provided IPv6 CIDR block to all VPCs with Name that starts with "example-".
#>
function Add-VpcIpv6Cidr
{
    [Alias('vpc_ipv6_add')]
    [CmdletBinding(DefaultParameterSetName = 'VpcName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string[]]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory, Position = 0)]
        [string[]]
        $VpcName
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
        if (-not $_vpc_list)
        {
            Write-Error "No VPC was found for '$_filter_value'."
            return
        }

        # Loop through each VPC to perform the CIDR addition.
        $_vpc_list | ForEach-Object {

            # Generate a friendly display string for this VPC.
            $_format_vpc = $_ | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, 'Add new Amazon provided IPv6 CIDR block'))
            {
                try {
                    # Call the API to add the IPv6 CIDR to this VPC.
                    $_result = Register-EC2VpcCidrBlock -Verbose:$false -AmazonProvidedIpv6CidrBlock $true $_.VpcId

                    # Wait for the association to complete.
                    Write-Message -Progress $_cmdlet_name '|- Waiting for association to complete.'

                    $_counter = 0
                    do {
                        Start-Sleep 1; $_counter++

                        $_assoc_set = Get-EC2Vpc $_.VpcId -Verbose:$false -Filter @{
                            Name   = 'ipv6-cidr-block-association.association-id'
                            Values = $_result.Ipv6CidrBlockAssociation.AssociationId
                        } |
                        Select-Object -ExpandProperty Ipv6CidrBlockAssociationSet |
                        Where-Object AssociationId -eq $_result.Ipv6CidrBlockAssociation.AssociationId

                        $_state = $_assoc_set.Ipv6CidrBlockState.State

                    } while ($_state -ne 'associated' -and $_state -le 3)

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