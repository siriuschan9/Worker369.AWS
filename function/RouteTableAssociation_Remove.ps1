function Remove-RouteTableAssociation
{
    [Alias('rt_assoc_rm')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Alias('RouteTableAssociationId')]
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidatePattern('rtbassoc-[0-9a-f]{17}', ErrorMessage = 'Invalid Route Table Association ID.')]
        [string[]]
        $AssociationId
    )

    PROCESS
    {
        # Use snake_case
        $_assoc_id = $AssociationId

        # Query the list of Route Table Associations to remove first.
        try {
            $_assoc_list = Get-EC2RouteTable -Verbose:$false -Filter @{
                Name   = 'association.route-table-association-id';
                Values = $_assoc_id
            } |
            Select-Object -ExpandProperty Associations |
            Where-Object RouteTableAssociationId -in $_assoc_id
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }

        if (-not $_assoc_list)
        {
            Write-Error "No Route Table Association was found for '$_assoc_id'."
            return
        }

        $_assoc_list | ForEach-Object {

            $_assoc = $_

            if ($PSCmdlet.ShouldProcess("$($_.RouteTableAssociationId)", "Remove Route Table Association"))
            {
                try {
                    Unregister-EC2RouteTable -Verbose:$false -Confirm:$false $_assoc.RouteTableAssociationId
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