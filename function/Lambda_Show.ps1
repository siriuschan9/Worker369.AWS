function Show-Lambda
{
    [Alias('func_show')]
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param (
        [parameter(Position = 0)]
        [ValidateSet('Default', 'Logging', 'Invocation', 'CloudFormation', 'Network')]
        [string]
        $View = 'Default',

        [ValidateSet('Runtime', 'Type', 'Role', 'LogFormat', $null)]
        [string]
        $GroupBy = 'Runtime',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [scriptblock]
        $Where = {$true},

        [switch]
        $PassThru,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_where            = $Where
    $_pass_thru        = $PassThru.IsPresent
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_dash        = $_plain_text ? '-' : "$($PSStyle.Dim)-$($PSStyle.Reset)"

    $_select_definition = @{
        ApplicationLogLevel = {
            $_.LoggingConfig.ApplicationLogLevel
        }
        Architectures = {
            $_.Architectures -join "`n"
        }
        LastEvent = {
            $_last_event_lookup[$_.FunctionName] -as [datetime]
        }
        LastModified = {
            $_.LastModified -as [datetime]
        }
        LogFormat = {
            $_.LoggingConfig.LogFormat
        }
        LogGroup = {
            $_.LoggingConfig.LogGroup
        }
        LogicalId = {
            $_tags_lookup[$_.FunctionArn]['aws:cloudformation:logical-id']
        }
        Memory = {
            New-NumberInfo $_.MemorySize
        }
        Name = {
            $_.FunctionName
        }
        Pull = {
            $_pull_lookup[$_.FunctionArn]
        }
        Push = {
            $_push_lookup[$_.FunctionArn]
        }
        Role = {
            ($_.Role -split '/')[-1]
        }
        Runtime = {
            $_.Runtime
        }
        SecurityGroup = {
            $_sg_id_list = $_.VpcConfig.SecurityGroupIds
            $_sg_id_list `
                ? ($_sg_id_list | ForEach-Object { $_sg_lookup[$_] | Get-ResourceString -IdPropertyName 'GroupId' -NamePropertyName 'GroupName' -PlainText:$_plain_text }) `
                : $_dash
        }
        Size = {
            New-ByteInfo -MetricSystem SI $_.CodeSize
        }
        StackName = {
            $_tags_lookup[$_.FunctionArn]['aws:cloudformation:stack-name']
        }
        SystemLogLevel = {
            $_.LoggingConfig.SystemLogLevel
        }
        Subnet = {
            $_subnet_id_list = $_.VpcConfig.SubnetIds
            $_subnet_id_list `
                ? ($_subnet_id_list | ForEach-Object { $_subnet_lookup[$_] | Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text }) `
                : $_dash
        }
        Timeout = {
            $_.Timeout
        }
        Type = {
            $_.PackageType
        }
        Vpc = {
            $_vpc_id = $_.VpcConfig.VpcId
            $_vpc_id `
                ? ($_vpc_lookup[$_vpc_id] | Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text) `
                : $_dash
        }
    }

    $_view_definition = @{
        Default = @(
            'Name', 'Architectures', 'Runtime', 'Type', 'Role', 'Memory', 'Timeout', 'Size', 'LastModified', 'LastEvent'
        )
        Logging = @(
            'Name', 'LogGroup', 'LogFormat', 'SystemLogLevel', 'ApplicationLogLevel', 'LastEvent'
        )
        Invocation = @(
            'Name', 'Push', 'Pull'
        )
        CloudFormation = @(
            'Name', 'StackName', 'LogicalId', 'LastModified', 'LastEvent'
        )
        Network = @(
            'Name', 'Vpc', 'Subnet', 'SecurityGroup'
        )
    }

    # Apply default sort order.
    if (
        $_group_by -eq 'Runtime' -and
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1) # => Sort by FunctionName
    }

    try {
        $_lambda_list = Get-LMFunctionList -Verbose:$false
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    # If there are no functions returned, exit early.
    if (-not $_lambda_list) { return }

    # Collect last event data if we are presenting these views.
    if ($_view -in @('Default', 'Logging', 'CloudFormation'))
    {
        Write-Verbose 'Retrieving Logging details.'

        # Define a hashtable to collect last event timestamp for each function.
        $_last_event_lookup = @{}

        # Collect last event timestamp.
        foreach ($_function in $_lambda_list)
        {
            try {
                $_last_event_lookup[$_function.FunctionName] = `
                    Get-CWLLogStream `
                        -Verbose:$false `
                        -LogGroupName $_function.LoggingConfig.LogGroup `
                        -Descending $true `
                        -Limit 1 `
                        -OrderBy LastEventTime |
                    Select-Object -First 1 -ExpandProperty LastEventTimestamp
            }
            catch [Amazon.CloudWatchLogs.Model.ResourceNotFoundException] {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Re-throw caught exception.
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
    }

    # Collect push & pull trigger data if we are presenting in these views.
    if ($_view -in @('Invocation'))
    {
        Write-Verbose 'Retrieving trigger details.'

        # Define a hashtable to collect push and pull triggers.
        $_pull_lookup = @{}
        $_push_lookup = @{}

        # Collect push triggers.
        foreach ($_function in $_lambda_list)
        {
            try {
                $_permission_list = `
                    Get-LMPolicy -Verbose:$false $_function.FunctionName |
                    Select-Object -ExpandProperty Policy | ConvertFrom-Json -Depth 9 |
                    Select-Object -ExpandProperty Statement
            }
            catch [Amazon.Lambda.Model.ResourceNotFoundException] {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                $_permission_list = $null
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Re-throw caught exception.
                $PSCmdlet.ThrowTerminatingError($_)
            }

            foreach ($_permission in $_permission_list)
            {
                if ($_permission.Effect -eq 'Allow')
                {
                    $_source_arn_list = $null
                    $_source_arn_list = $_permission.Condition.ArnLike.'AWS:SourceArn' -as [string[]]

                    $_service_list = $null
                    $_service_list = $_permission.Principal.Service -as [string[]]

                    $_push_lookup[$_function.FunctionArn] += ($_source_arn_list ?? $_service_list)
                }
            }
        }

        # Collect pull triggers.
        try {
            $_event_source_mapping_list = Get-LMEventSourceMappingList -Verbose:$false
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught exception.
            $PSCmdlet.ThrowTerminatingError($_)
        }

        foreach ($_mapping in $_event_source_mapping_list)
        {
            $_pull_lookup[$_mapping.FunctionArn] += $_mapping.EventSourceArn -as [string[]]
        }
    }

    # Collect tags if presenting in these views.
    if ($_view -in @('CloudFormation'))
    {
        Write-Verbose 'Retrieving tags.'

        $_tags_lookup = @{}

        try{
            foreach ($_function in $_lambda_list)
            {
                $_tags_lookup[$_function.FunctionArn] = Get-LMResourceTag -Verbose:$false $_function.FunctionArn
            }
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught exception.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    # Collect network details.
    if ($_view -in @('Network'))
    {
        Write-Message -Progress $_cmdlet_name 'Retrieving network details.'
        try {
            $_vpc_config_list = $_lambda_list | Select-Object -ExpandProperty VpcConfig
            $_vpc_list = $_vpc_config_list | Select-Object -Unique -ExpandProperty VpcId
            $_subnet_list = $_vpc_config_list | Select-Object -Unique -ExpandProperty SubnetIds | ForEach-Object {$_}
            $_sg_list = $_vpc_config_list | Select-Object -Unique -ExpandProperty SecurityGroupIds | ForEach-Object {$_}

            $_vpc_lookup = Get-EC2Vpc -Verbose:$false -Filter @{
                Name = 'vpc-id'
                Values = $_vpc_list
            } | Group-Object -AsHashTable VpcId

            $_subnet_lookup = Get-EC2Subnet -Verbose:$false -Filter @{
                Name = 'subnet-id'
                Values = $_subnet_list
            } | Group-Object -AsHashTable SubnetId

            $_sg_lookup = Get-EC2SecurityGroup -Verbose:$false -Filter @{
                Name = 'group-id'
                Values = $_sg_list
            } | Group-Object -AsHashTable GroupId
        }
        catch {
            # Remove caught exception emitted into $Error list.
            Pop-ErrorRecord $_

            # Re-throw caught exception.
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    if ($_view -in @('Version'))
    {
        Write-Verbose 'Retrieving versions'

        $_versions_lookup = @{}

        foreach ($_function in $_lambda_list)
        {
            try{
                foreach ($_function in $_lambda_list)
                {
                    $_versions_lookup[$_function.FunctionArn] = `
                        Get-LMVersionsByFunction -Verbose:$false $_function.FunctionArn
                }
            }
            catch {
                # Remove caught exception emitted into $Error list.
                Pop-ErrorRecord $_

                # Re-throw caught exception.
                $PSCmdlet.ThrowTerminatingError($_)
            }
        }
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Generate output after sorting and exclusion.
    $_output = $_lambda_list `
        | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list | Where-Object $_where

    # Print out the output. If -PassThru, put the objects in the pipeline.
    if ($_pass_thru) {
        $_output
    } else {
        if ($global:EnableHtmlOutput) {
            $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
        } else {
            $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
        }
    }
}
