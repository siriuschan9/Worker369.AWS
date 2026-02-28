<#
.SYNOPSIS
The cmdlet attaches an Internet Gateway to a VPC.

.PARAMETER InternetGatewayId
If using -InternetGatewayId paramter, pair it with -VpcId Parameter. See example 1.

.PARAMETER VpcId
If using -VpcId paramter, pair it with -InternetGatewayId Parameter. See example 1.

.PARAMETER InternetGatewayName
The -InternetGatewayName Parameter specifies the Name of the Internet Gateway. It must be unique. Else, the cmdlet will fail. See example 2.

.PARAMETER VpcName
The -VpcName Parameter specifies the Name of the VPC. It must be unique. Else, the cmdlet will fail. See example 2.

.EXAMPLE
Mount-InternetGateway -InternetGatewayId igw-12345678901234567 -VpcId vpc-12345678901234567

This example attaches the Internet Gateway igw-1234567890abcdef0 to VPC vpc-1234567890abcdef0.

.EXAMPLE
Mount-InternetGateway igw-example-2 vpc-example-2

This example finds the Internet Gateway named "igw-example-2" and attaches it to a VPC named "vpc-example-2".
#>

function Mount-InternetGateway
{
    [Alias('igw_mount')]
    [CmdletBinding(DefaultParameterSetName = 'InternetGatewayName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'InternetGatewayId', Mandatory)]
        [ValidatePattern('^igw-[0-9a-f]{17}$', ErrorMessage = 'Invalid InternetGatewayId.')]
        [string]
        $InternetGatewayId,

        [Parameter(ParameterSetName = 'InternetGatewayId', Mandatory)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $VpcId,

        [Parameter(ParameterSetName = 'InternetGatewayName', Mandatory, Position = 0)]
        [string]
        $InternetGatewayName,

        [Parameter(ParameterSetName = 'InternetGatewayName', Mandatory, Position = 1)]
        [string]
        $VpcName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_igw_name = $InternetGatewayName
        $_igw_id   = $InternetGatewayId
        $_vpc_name = $VpcName
        $_vpc_id   = $VpcId

        # Configure the filter to query the Internet Gateway.
        $_igw_filter_name  = $_param_set -eq 'InternetGatewayId' ? 'internet-gateway-id' : 'tag:Name'
        $_igw_filter_value = $_param_set -eq 'InternetGatewayId' ? $_igw_id : $_igw_name

        # Configure the filter to query the VPC.
        $_vpc_filter_name  = $_param_set -eq 'InternetGatewayId' ? 'vpc-id' : 'tag:Name'
        $_vpc_filter_value = $_param_set -eq 'InternetGatewayId' ? $_vpc_id : $_vpc_name

        # Query the Internet Gateway and VPC first.
        try {
            $_igw_list = Get-EC2InternetGateway -Verbose:$false -Filter @{
                Name   = $_igw_filter_name
                Values = $_igw_filter_value
            }

            $_vpc_list = Get-EC2Vpc -Verbose:$false -Filter @{
                Name   = $_vpc_filter_name
                Values = $_vpc_filter_value
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        # If no Internet Gateway matched the filter value, exit early.
        if ($_igw_list.Count -eq 0)
        {
            Write-Error "No Internet Gateway was found for '$_igw_filter_value'."
            return
        }

        # If multiple Internet Gateways matched the filter value, exit early.
        if ($_igw_list.Count -gt 1)
        {
            Write-Error  "Multiple Internet Gateways were found for '$_igw_filter_value'."
            return
        }

        # If no VPC matched the filter value, exit early.
        if ($_vpc_list.Count -eq 0)
        {
            Write-Error "No VPC was found for '$_vpc_filter_value'."
            return
        }

        # If multiple VPC matched the filter value, exit early.
        if ($_vpc_list.Count -gt 1)
        {
            Write-Error "Multiple VPCs was found for '$_vpc_filter_value'."
            return
        }

        # Save a reference to the filtered Internet Gateway and VPC.
        $_igw = $_igw_list[0]
        $_vpc = $_vpc_list[0]

        # Generate a friendly display string for the Internet Gateway and VPC.
        $_format_igw = $_igw | Get-ResourceString `
            -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        $_format_vpc = $_vpc | Get-ResourceString `
            -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

        # Display What-If/Confirmation prompt.
        if ($PSCmdlet.ShouldProcess($_format_vpc, "Attach Internet Gateway $_format_igw")) {

            # Call the API to attach the Internet Gateway.
            try {
                Add-EC2InternetGateway -Verbose:$false $_vpc.VpcId $_igw.InternetGatewayId
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