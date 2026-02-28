function Approve-VpcPeering
{
    [CmdletBinding(DefaultParameterSetName = "VpcPeeringConnectionName", SupportsShouldProcess, ConfirmImpact = 'High')]
    [Alias('pcx_accept')]
    param (
        [Parameter(
            ParameterSetName = "VpcPeeringConnectionId", Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName
        )]
        [ValidatePattern('^pcx-[0-9a-f]{17}$')]
        [string]
        $VpcPeeringConnectionId,

        [Parameter(ParameterSetName = "VpcPeeringConnectionName", Mandatory, Position = 0)]
        [string]
        $VpcPeeringConnectionName
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        # Use snake_case.
        $_pcx_id   = $VpcPeeringConnectionId
        $_pcx_name = $VpcPeeringConnectionName

        # Configure the filter to query the Subnet.
        $_filter_name  = $_param_set -eq 'VpcPeeringConnectionId' ? 'vpc-peering-connection-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcPeeringConnectionId' ? $_pcx_id : $_pcx_name

        # Query the list of Subnet to rename first.
        try {
                $_pcx_list = Get-EC2VpcPeeringConnection -Verbose:$false -Filter @{
                    Name = $_filter_name;
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
            if ($PSCmdlet.ShouldProcess($_format_pcx, "Accept VPC Peering request"))
            {
                # Call the API to accept the peering.
                try {
                    Approve-EC2VpcPeeringConnection -Verbose:$false $_.VpcPeeringConnectionId | Out-Null

                    $_updated_pcx = Get-EC2VpcPeeringConnection -Verbose:$false $_.VpcPeeringConnectionId

                    Write-Message -Output `
                        "VpcPeeringConnectionId: $($_.VpcPeeringConnectionId) => Status: $($_updated_pcx.Status.Code)"
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

# pending-acceptance | failed | expired | provisioning | active | deleting | deleted | rejected