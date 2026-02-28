function Enable-VpcPeeringDns
{
    [CmdletBinding(DefaultParameterSetName = 'VpcPeeringConnectionName', SupportsShouldProcess)]
    [Alias('pcx_dns_en')]
    param (
        [Parameter(
            ParameterSetName = 'VpcPeeringConnectionId', Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName
        )]
        [ValidatePattern('^pcx-[0-9a-f]{17}$')]
        [string]
        $VpcPeeringConnectionId,

        [Parameter(ParameterSetName = 'VpcPeeringConnectionName', Mandatory, Position = 0)]
        [string]
        $VpcPeeringConnectionName,

        [switch]
        $Left,

        [switch]
        $Right
    )

    BEGIN {
        if (-not $PSBoundParameters.ContainsKey('Left') -and -not $PSBoundParameters.ContainsKey('Right'))
        {
            $_error_record = New-ErrorRecord `
                -ErrorMessage (
                    'You must specify at least one of -Left and -Right parameters.' +
                    'Use ''-Left'' to accept DNS on requester side.' +
                    'Use ''-Right'' to accept DNS on accepter side.'
                 ) `
                -ErrorId 'UnspecifiedPeeringSide' `
                -ErrorCategory NotSpecified

            $PSCmdlet.ThrowTerminatingError($_error_record)
        }

        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS {
        # Use snake_case.
        $_pcx_id   = $VpcPeeringConnectionId
        $_pcx_name = $VpcPeeringConnectionName
        $_left     = $Left.IsPresent
        $_right    = $Right.IsPresent

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'VpcPeeringConnectionId' ? 'vpc-peering-connection-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcPeeringConnectionId' ? $_pcx_id : $_pcx_name

        # Query the list of Subnet to rename first.
        try {
            $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                Name   = $_filter_name;
                Values = $_filter_value
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

        # If no VPC Peering Connection matched the filter value, exit early.
        if (-not $_pcx_list)
        {
            Write-Error "No VPC Peering Connection was found for '$_filter_value'."
            return
        }

        # Loop through each Peering Connection to perform the renaming.
        $_pcx_list | ForEach-Object {

            # Generate a friendly display string for the Peering Connection.
            $_format_pcx = $_ | Get-ResourceString `
                -IdPropertyName 'VpcPeeringConnectionId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

            # Display What-If/Confirm prompt.
            if ($PSCmdlet.ShouldProcess($_format_pcx, "Enable DNS resolution from remote VPC."))
            {
                # We need to build the parameters dynamically
                # because we cannot specify the option which we do not have the permission to change
                # i.e. the VPC belongs to a different account.
                $_params = @{
                    Verbose = $false
                    VpcPeeringConnectionId = $_.VpcPeeringConnectionId
                }

                if ($_left) {
                    $_params.Add('RequesterPeeringConnectionOptions_AllowDnsResolutionFromRemoteVpc', $_left)
                }

                if ($_right) {
                    $_params.Add('AccepterPeeringConnectionOptions_AllowDnsResolutionFromRemoteVpc', $_right)
                }

                # Call the API to enable DNS resolution from remote VPC.
                try {
                    Edit-EC2VpcPeeringConnectionOption @_params | Out-Null
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