<#
.SYNOPSIS
This cmdlet removes one or more Internet Gateway(s).
You can specify the Internet Gateway(s) using either the -InternetGatewayId or -InternetGatewayName Parameter.

.PARAMETER InternetGatewayId
The -InternetGatewayId Parameter specifies the Internet Gateway ID.
You can also pass in an array of Internet Gateway IDs.
This parameter supports pipeline inputs.
See example 1.

.PARAMETER InternetGatewayName
The -Name Parameter specifies the Internet Gateway's Name.
You can use glob wildcards to match multiple Internet Gateways.
You can also pass in an array of Names.
See example 2.

.EXAMPLE
Remove-Igw -InternetGatewayId igw-1234567890abcdef0

This example removes the Internet Gateway igw-1234567890abcdef0.

.EXAMPLE
Remove-Igw -InternetGatewayName example-*

This example removes all Internet Gateways with Name that starts with "example-".

#>
function Remove-InternetGateway
{
    [Alias('igw_rm')]
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

        # Loop through each Internet Gateway to perform the deletion.
        $_igw_list | ForEach-Object {

            # Generate a friendly display string for the Internet Gateway.
            $_format_igw = $_ | Get-ResourceString `
                -IdPropertyName 'InternetGatewayId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirmation prompt.
            if ($PSCmdlet.ShouldProcess($_format_igw, 'Remove Internet Gateway'))
            {
                # Call the API to remove the Internet Gateway.
                try {
                    Remove-EC2InternetGateway -Verbose:$false -Confirm:$false $_.InternetGatewayId
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