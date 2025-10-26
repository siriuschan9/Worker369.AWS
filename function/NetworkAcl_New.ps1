function New-NetworkAcl
{
    [Alias('nacl_add')]
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ParameterSetName = 'VpcId', Mandatory)]
        [ValidatePattern('^vpc-[0-9a-f]{17}$', ErrorMessage = 'Invalid VpcId.')]
        [string]
        $VpcId,

        [Parameter(ParameterSetName = 'VpcName', Mandatory)]
        [string]
        $VpcName,

        [Parameter(Position = 0)]
        [string]
        $Name,

        [Parameter()]
        [Amazon.EC2.Model.Tag[]]
        $Tag
    )

    BEGIN
    {
        # For easy pick up.
        $_param_set = $PSCmdlet.ParameterSetName
    }

    PROCESS
    {
        $_vpc_id   = $VpcId
        $_vpc_name = $VpcName
        $_name     = $Name
        $_tag      = $Tag

        # Configure the filter to query the VPC.
        $_filter_name  = $_param_set -eq 'VpcId' ? 'vpc-id' : 'tag:Name'
        $_filter_value = $_param_set -eq 'VpcId' ? $_vpc_id : $_vpc_name

        # Query the VPC to add the subnet first.
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

        # If multiple VPC matched the filter value, exit early.
        if ($_vpc_list.Count -gt 1)
        {
            Write-Error "Multiple VPC was found for '$_filter_value'. It must matched exactly one VPC."
            return
        }

        # Save a reference to the filtered VPC.
        $_vpc = $_vpc_list[0]

        # Prepare TagSpecification parameter.
        $_make_tags_with_name    = { New-TagSpecification -ResourceType network-acl -Tag $_tag -Name $_name}
        $_make_tags_without_name = { New-TagSpecification -ResourceType network-acl -Tag $_tag }
        $_has_name               = $PSBoundParameters.ContainsKey('Name')
        $_tag_specification      = $_has_name ? (& $_make_tags_with_name) : (& $_make_tags_without_name)

         # Generate a friendly display string for the VPC.
        $_format_vpc = $_vpc | Get-ResourceString `
            -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText

        # Display What-If/Confirm prompt.
        if (-not $PSCmdlet.ShouldProcess($_format_vpc, 'Create New Network ACL')) { return }

        try {
            $_new_acl = New-EC2NetworkAcl -Verbose:$false -VpcId $_vpc.VpcId -TagSpecification $_tag_specification

            Write-Message -Output "|- NetworkAclId: $($_new_acl.NetworkAclId)"
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)
        }
    }
}