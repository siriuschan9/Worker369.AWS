<#
.SYNOPSIS
This cmdlet renames one or more Internet Gateway(s).
You can specify the Internet Gateway(s) using either the -Name or -InternetGatewayId Parameter.

.PARAMETER InternetGatewayId
The -InternetGatewayId Parameter specifies the Internet Gateway ID.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER InternetGatewayName
The -InternetGatewayName Parameter specifies the Internet Gateway's Name.
You can use glob wildcards to match multiple Internet Gateways.
See example 2.

.PARAMETER NewName
The -NewName Parameter specifies the new Name.

.EXAMPLE
Rename-InternetGateway -InternetGatewayId igw-12345678901234560 -NewName 'example-1-new'

This example renames the Internet Gateway igw-12345678901234560 to "example-1-new".

.EXAMPLE
Rename-InternetGateway -InternetGatewayName example-1 -NewName example-2

This example renames the Internet Gateway named "example-2" to "example-2-new".
#>
function Rename-InternetGateway
{
    [Alias('igw_rn')]
    [CmdletBinding(DefaultParameterSetName = 'InternetGatewayName', SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'InternetGatewayId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^igw-[0-9a-f]{17}$', ErrorMessage = 'Invalid InternetGatewayId.')]
        [string]
        $InternetGatewayId,

        [Parameter(ParameterSetName = 'InternetGatewayName', Mandatory, Position = 0)]
        [string]
        $InternetGatewayName,

        [Parameter(Mandatory, Position = 1)]
        [string]
        $NewName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_igw_id   = $InternetGatewayId
        $_igw_name = $InternetGatewayName
        $_new_name = $NewName

        # Configure the filter to query the Internet Gateway.
        $_filter_name  = $_param_set -eq 'InternetGatewayId' ? 'internet-gateway-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'InternetGatewayId' ? $_igw_id : $_igw_name

        # Query the list of Internet Gateways to remove first.
        try {
            $_igw_list = Get-EC2InternetGateway -Verbose:$false -Filter @{Name = $_filter_name; Values = $_filter_value}
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
            Write-Error "No IGW was found for '$_filter_value'."
            return
        }

        # Loop through each Internet Gateway to perform the renaming.
        $_igw_list | ForEach-Object {

            # Generate a friendly display string for the Internet Gateway.
            $_format_igw = $_ | Get-ResourceString -IdPropertyName `
                'InternetGatewayId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_igw, 'Rename Internet Gateway'))
            {
                # Call the API to revalue the Name Tag.
                try {
                    New-EC2Tag -Verbose:$false -Tag @{Key = 'Name'; Value = $_new_name} $_.InternetGatewayId
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