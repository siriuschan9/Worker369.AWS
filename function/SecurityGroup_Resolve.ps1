function Resolve-SecurityGroup
{
    [CmdletBinding(DefaultParameterSetName = 'TagName')]
    [Alias('sg_resolve')]
    param (
        [Parameter(ParameterSetName = 'GroupId', Mandatory, ValueFromPipelineByPropertyName)]
        [ValidatePattern('^sg-[0-9a-f]{17}$', ErrorMessage = 'Invalid GroupId.')]
        [string]
        $GroupId,

        [Parameter(ParameterSetName = 'TagName', Position = 0, Mandatory)]
        [string]
        $TagName,

        [Parameter(ParameterSetName = 'GroupName', Position = 0, Mandatory)]
        [string]
        $GroupName
    )

    PROCESS
    {
        $_group_id   = $GroupId
        $_group_name = $GroupName
        $_tag_name   = $TagName

        $_param_set = $PSCmdlet.ParameterSetName

        switch ($_param_set)
        {
            'GroupId' {
                $_filter_name  = 'group-id'
                $_filter_value = $_group_id
            }
            'GroupName' {
                $_filter_name  = 'group-name'
                $_filter_value = $_group_name
            }
            'TagName' {
                $_filter_name  = 'tag:Name'
                $_filter_value = $_tag_name
            }
        }

        try {
            # Try to query the Security Group.
            Write-Verbose "Retrieving Security Group."
            $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
                Name   = $_filter_name
                Values = $_filter_value
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught exception.
            $PSCmdlet.ThrowTerminatingError($_)
        }

        # If no Security Groups matched the filter value, exit early.
        if (-not $_sg_list)
        {
            Write-Error "No Security Groups were found for '$_filter_value'."
            return
        }

        # If multiple Security Groups matched the filter value, exit early.
        if ($_sg_list.Count -gt 1)
        {
            Write-Error (
                "Multiple Security Groups were found for '$_filter_value'. " +
                "It must match one Security Group only.")
            return
        }

        # Save a reference to the filtered Security Group.
        $_sg = $_sg_list[0]

        try {
            $_eni_list = Get-EC2NetworkInterface -Verbose:$false -Filter @{ Name = 'group-id'; Values = $_sg.GroupId }

            $_eni_list |
            Select-Object -ExpandProperty PrivateIpAddresses |
            Select-Object -ExpandProperty PrivateIpAddress |
            Split-String "`n"

            $_eni_list |
            Select-Object -ExpandProperty Ipv6Addresses |
            Select-Object -ExpandProperty Ipv6Address |
            Split-String "`n"
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Report error as non-terminating.
            $PSCmdlet.WriteError($_)

            # Exit early.
            return
        }
    }
}