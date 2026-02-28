<#
.SYNOPSIS
This cmdlet detaches an Internet Gateway from a VPC.

.PARAMETER InternetGatewayId
The -InternetGatewayId Parameter specifies the Internet Gateway ID.
You can also pass in an array of Internet Gateway IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER InternetGatewayName
The -InternetGatewayName Parameter specifies the Internet Gateway's Name.
You can use glob wildcards to match multiple Internet Gateways.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Remove-InternetGateway -Confirm:$false -InternetGatewayId igw-1234567890abcdef0

This example detaches the Internet Gateway igw-1234567890abcdef0 from the VPC which it is attached to.

.EXAMPLE
Dismount-InternetGateway -Confirm:$false example-*

This example detaches all Internet Gateways with Name that starts with "example-" from the VPCs which they are attached to.
#>

function Dismount-InternetGateway
{
    [Alias('igw_umount')]
    [CmdletBinding(DefaultParameterSetName = 'InternetGatewayName', SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(ParameterSetName = 'InternetGatewayId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('igw-[0-9a-f]{17}', ErrorMessage = 'Invalid InternetGatewayId.')]
        [string[]]
        $InternetGatewayId,

        [Parameter(ParameterSetName = 'InternetGatewayName', Mandatory, Position = 0)]
        [string[]]
        $InternetGatewayName
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

        # Configure the filter to query the Internet Gateway.
        $_filter_name  = $_param_set -eq 'InternetGatewayId' ? 'internet-gateway-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'InternetGatewayId' ? $_igw_id : $_igw_name

        # Query the list of Internet Gateways and VPC first.
        try {
            $_igw_list = Get-EC2InternetGateway -Verbose:$false -Filter @{
                Name   = $_filter_name
                Values = $_filter_value
            }

            if ($_igw_list)
            {
                $_vpc_lookup = Get-EC2Vpc -Verbose:$false -Filter @{
                    Name   = 'vpc-id'
                    Values = $_igw_list.Attachments.VpcId
                } | Group-Object -AsHashTable VpcId
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
        if (-not $_igw_list)
        {
            Write-Error "No Internet Gateway was found for '$_filter_value'."
            return
        }

        # Loop through each Internet Gateway to perform the detachment.
        $_igw_list | ForEach-Object {

            # Generate a friendly display string for the Internet Gateway.
            $_igw        = $_
            $_format_igw = $_igw | Get-ResourceString `
                -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # If Internet Gateway is not attached to a VPC, exit early.
            if (-not ($_vpc_id = $_igw.Attachments.VpcId))
            {
                Write-Error "$_format_igw is not attached to a VPC."
                return
            }

            # Generate a friendly display string for the VPC.
            $_vpc        = $_vpc_lookup[$_vpc_id]
            $_format_vpc = $_vpc | Get-ResourceString `
                -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_vpc, "Detach Internet Gateway $_format_igw"))
            {
                # Call the API to detach the Internet Gateway.
                try {
                    Dismount-EC2InternetGateway -Verbose:$false -Confirm:$false $_vpc.VpcId $_igw.InternetGatewayId
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
