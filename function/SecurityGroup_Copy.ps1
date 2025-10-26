function Copy-SecurityGroup
{
    [CmdletBinding(DefaultParameterSetName = 'TagName', SupportsShouldProcess)]
    [Alias('sg_cp')]
    param (
        [Parameter(ParameterSetName = 'GroupId', Mandatory, Position = 0)]
        [ValidatePattern('^sg-[0-9a-f]{17}$', ErrorMessage = 'Invalid SrcGroupId.')]
        [string]
        $SrcGroupId,

        [Parameter(ParameterSetName = 'GroupId', Mandatory, Position = 1)]
        [ValidatePattern('^sg-[0-9a-f]{17}$', ErrorMessage = 'Invalid DstGroupId.')]
        [string]
        $DstGroupId,

        [Parameter(ParameterSetName = 'TagName', Mandatory, Position = 0)]
        [string]
        $SrcTagName,

        [Parameter(ParameterSetName = 'TagName', Mandatory, Position = 1)]
        [string]
        $DstTagName
    )

    # For easy pickup.
    $_param_set   = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_src_group_id = $SrcGroupId
    $_dst_group_id = $DstGroupId
    $_src_tag_name = $SrcTagName
    $_dst_tag_name = $DstTagName

    # Configure the filter to query the Security Groups.
    $_src_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
    $_src_filter_value = $_param_set -eq 'GroupId' ? $_src_group_id : $_src_tag_name
    $_dst_filter_name  = $_param_set -eq 'GroupId' ? 'group-id' : 'tag:Name'
    $_dst_filter_value = $_param_set -eq 'GroupId' ? $_dst_group_id : $_dst_tag_name

    # Query the Security Group to copy first.
    try {
        $_src_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
            Name = $_src_filter_name; Values = $_src_filter_value
        }

        $_dst_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
            Name = $_dst_filter_name; Values = $_dst_filter_value
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If no Security Group matched the filter value, exit early.
    if (-not $_src_sg_list) {
        Write-Error "No Security Group was found for '$_src_filter_value'."
        return
    }

    if (-not $_dst_sg_list) {
        Write-Error "No Security Group was found for '$_dst_filter_value'."
        return
    }

    # If multiple Security Groups matched the filter value, exit early.
    if ($_src_sg_list.Count -gt 1) {
        Write-Error "Multiple Security Groups were found for '$_src_filter_value'. It must match one Security Group."
        return
    }

    if ($_dst_sg_list.Count -gt 1) {
        Write-Error "Multiple Security Groups were found for '$_dst_filter_value'. It must match one Security Group."
        return
    }

    # Save a referece to the filtered Security Groups.
    $_src_sg = $_src_sg_list[0]
    $_dst_sg = $_dst_sg_list[0]

    # Generate a friendly display string for the Security Groups.
    $_format_src_sg = $_src_sg | Get-ResourceString `
        -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

    $_format_dst_sg = $_dst_sg | Get-ResourceString `
        -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -StringFormat IdAndName -PlainText

    # Display What-If/Confirm prompt.
    if ($PSCmdlet.ShouldProcess("Src SG: $_format_src_sg | Dst SG: $_format_dst_sg", "Copy Security Group."))
    {
        try {
            # All the API to create the Security Group Rules.
            Grant-EC2SecurityGroupIngress -Verbose:$false `
                -IpPermission $_src_sg.IpPermissions $_dst_sg.GroupId | Out-Null

            Grant-EC2SecurityGroupEgress -Verbose:$false `
                -IpPermission $_src_sg.IpPermissionsEgress $_dst_sg.GroupId | Out-Null
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught error.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

# SrcGroupId
Register-ArgumentCompleter -ParameterName 'SrcGroupId' -CommandName 'Copy-SecurityGroup' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_dst_group_id = $_fake_bound_parameters['DstGroupId']

    $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name   = 'group-id'
        Values = "$_word_to_complete*"
    } | Where-Object GroupId -ne $_dst_group_id

    if (-not $_sg_list) { return }

    $_align = $_sg_list.SecurityGroupId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_sg_list | Get-HintItem -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# DstGroupId
Register-ArgumentCompleter -ParameterName 'DstGroupId' -CommandName 'Copy-SecurityGroup' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_src_group_id = $_fake_bound_parameters['SrcGroupId']

    $_sg_list = Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name   = 'group-id'
        Values = "$_word_to_complete*"
    } | Where-Object GroupId -ne $_src_group_id

    if (-not $_sg_list) { return }

    $_align = $_sg_list.SecurityGroupId.Length | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

    $_sg_list | Get-HintItem -IdPropertyName 'GroupId' -TagPropertyName 'Tags' -Align $_align |
    Sort-Object | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_.ResourceId,    # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# SrcGroupName
Register-ArgumentCompleter -ParameterName 'SrcTagName' -CommandName 'Copy-SecurityGroup' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_dst_tag_name = $_fake_bound_parameters['DstTagName']

    Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name = 'tag:Name'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
    Select-Object -Unique -ExpandProperty Value | Where-Object { $_ -ne $_dst_tag_name } | Sort-Object |
    ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}

# SrcGroupName
Register-ArgumentCompleter -ParameterName 'DstTagName' -CommandName 'Copy-SecurityGroup' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_src_tag_name = $_fake_bound_parameters['SrcTagName']

    Get-EC2SecurityGroup -Verbose:$false -Filter @{
        Name = 'tag:Name'
        Values = "$_word_to_complete*"
    } |
    Select-Object -ExpandProperty Tags | Where-Object Key -eq 'Name' |
    Select-Object -Unique -ExpandProperty Value | Where-Object { $_ -ne $_src_tag_name } | Sort-Object |
    ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}