function Show-Ec2
{
    [CmdletBinding()]
    [Alias('ec2_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default', 'Network', 'Status', 'Security', 'Sizing', 'Storage')]
        [string]
        $View = 'Default',

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('State', 'Vpc')]
        [string]
        $GroupBy = 'State',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # Use snake_case.
    $_view             = $View
    $_filter           = $Filter
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    # For easy pick-up later.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    # Each view defines an array of property names.
    $_view_definition = @{
        Default = @(
            'InstanceId', 'Name', 'State', 'InstanceType', 'AvailabilityZone', 'PrivateIpAddress', 'PublicIpAddress',
            'Ipv6Address'
        )
        Network = @(
            'InstanceId', 'Name', 'NetworkInterface', 'Subnet', 'Vpc'
        )
        Platform = @(
            'InstanceId', 'Name',  'InstanceType', 'Architecture', 'CurrentInstanceBootMode', 'PlatformDetails',
            'ImageId', 'ImageName'
        )
        Status = @(
            'InstanceId', 'Name', 'State', 'SystemStatus', 'InstanceStatus', 'AlarmStatus'
        )
        Security = @(
            'InstanceId', 'Name', 'KeyName', 'InstanceProfile', 'SecurityGroups'
        )
        Sizing = @(
            'InstanceId', 'Name', 'InstanceType', 'CpuCredits', 'VCpu', 'Memory', 'NetworkPerformance'
        )
        Storage = @(
            'InstanceId', 'Name', 'RootVolume', 'RootDeviceName', 'AttachedVolumes', 'TotalStorage'
        )
    }

    # Hashtable for Select-Object.
    $_select_definition = @{
        Architecture            = { $_.Architecture }
        AvailabilityZone        = { $_subnet_lookup[$_.SubnetId].AvailabilityZone }
        AttachedVolumnes        = { $_.BlockDeviceMappings.Count }
        CpuCredits              = { $_credit_lookup[$_.InstanceId].CpuCredits }
        CurrentInstanceBootMode = { $_.CurrentInstanceBootMode }
        ImageId                 = { $_.ImageId }
        ImageName               = { Get-EC2Image -Verbose:$false -ImageId $_.ImageId -Select Images.Name }
        InstanceId              = { $_.InstanceId }
        InstanceProfile         = { $_.IamInstanceProfile.Arn -replace '^arn:aws:iam::\d{12}:instance-profile\/' }
        InstanceStatus          = { $_status_lookup[$_.InstanceId].Status.Status }
        InstanceType            = { $_.InstanceType }
        Ipv6Address             = { $_.Ipv6Address }
        KeyName                 = { $_.KeyName }
        Memory                  = { $_type_lookup[$_.InstanceType].NetworkInfo.NetworkPerformance }
        Name                    = { $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value }
        NetworkPerformance      = { $_type_lookup[$_.InstanceType].NetworkInfo.NetworkPerformance }
        PlatformDetails         = { $_.PlatformDetails }
        PrivateIpAddress        = { $_.PrivateIpAddress }
        PublicIpAddress         = { $_.PublicIpAddress }
        RootDeviceName          = { $_.RootDeviceName }
        SecurityGroups          = { $_.SecurityGroups.GroupName }
        Subnet                  = { $_subnet_lookup[$_.SubnetId] | Get-DisplayName -ResourceIdPropertyName 'SubnetId' }
        SystemStatus            = { $_status_lookup[$_.InstanceId].SystemStatus.Status }
        VCpu                    = { $_type_lookup[$_.InstanceType].VCpuInfo.DefaultVCpus }
        Vpc                     = { $_vpc_lookup[$_.VpcId] | Get-DisplayName -ResourceIdPropertyName 'VpcId' }

        NetworkInterface = {
            $_.NetworkInterfaces | ForEach-Object {$_eni_lookup[$_.NetworkInterfaceId]} |
            Get-DisplayName -ResourceIdPropertyName 'NetworkInterfaceId'
        }
        RootVolume = {
            $_root_device_name = $_.RootDeviceName
            $_root_volume_id   = ($_.BlockDeviceMappings | Where-object {$_.DeviceName -eq $_root_device_name}).Ebs.VolumeId
            $_root_volume      = $_ebs_lookup[$_root_volume_id]
            $_root_volume      | Get-DisplayName -ResourceIdPropertyName 'VolumeId'
        }
        TotalStorage = {
            $_total = 0
            $_.BlockDeviceMappings.Ebs.ForEach({
                $_volume  = $_ebs_lookup[$_.VolumeId]
                $_total  += $_volume.Size
            })
            $_total
        }
    }

    # Declare hashtables
    $_alarm_lookup  = @{} # Hashtable to lookup cloudwatch alarm by Instance ID
    $_credit_lookup = @{} # Hashtable to lookup instance credit specification
    $_ebs_lookup    = @{} # Hashtable to lookup EBS volume by Volume ID
    $_eni_lookup    = @{} # Hashtable to lookup ENI info by Network Interface ID
    $_status_lookup = @{} # Hashtable to lookup instance status by Instance ID
    $_subnet_lookup = @{} # Hashtable to lookup subnet info by Subnet ID
    $_type_lookup   = @{} # Hashtable to lookup instance type info by Instance Type
    $_vpc_lookup    = @{} # Hashtable to lookup VPC info by VPC ID

    try {
        # Get all EC2
        Write-Message -Progress $_cmdlet_name 'Retrieving EC2 information.'
        $_ec2_list           = Get-EC2Instance -Verbose:$false -Select Reservations.Instances -Filter $_filter
        $_instance_id_list   = $_ec2_list.InstanceId
        $_instance_type_list = $_ec2_list.InstanceType | Select-Object -Unique
        $_volume_id_list     = $_ec2_list.BlockDeviceMappings.Ebs.VolumeId | Select-Object -Unique
        $_subnet_id_list     = $_ec2_list.SubnetId | Select-object -Unique
        $_vpc_id_list        = $_ec2_list.VpcId | Select-Object -Unique
        $_eni_id_list        = $_ec2_list.NetworkInterfaces.NetworkInterfaceId | Select-Object -Unique

        # Get all instances' credit specifications
        Write-Message -Progress $_cmdlet_name 'Retrieving CPU credit information.'
        $_credit_lookup = `
            Get-EC2CreditSpecification -Verbose:$false $_instance_id_list |
            Group-Object -AsHashTable InstanceId

        # Get all instances' statuses
        Write-Message -Progress $_cmdlet_name 'Retrieving status information.'
        $_status_lookup = `
            Get-EC2InstanceStatus -Verbose:$false $_instance_id_list |
            Group-Object -AsHashTable InstanceId

        # Get all instances' credit specifications.
        Write-Message -Progress $_cmdlet_name 'Retrieving CPU credit information.'
        $_credit_lookup = `
            Get-EC2CreditSpecification -Verbose:$false $_instance_id_list |
            Group-Object -AsHashTable InstanceId

        # Get all instance types
        Write-Message -Progress $_cmdlet_name 'Retrieving instance type information.'
        $_type_lookup = `
            Get-EC2InstanceType -Verbose:$false -Filter @{Name = 'instance-type'; Values = $_instance_type_list} |
            Group-Object -AsHashTable InstanceType

        # Get all EBS
        Write-Message -Progress $_cmdlet_name 'Retrieving EBS information.'
        $_ebs_lookup = `
            Get-EC2Volume -Verbose:$false -Filter @{Name = 'volume-id'; Values = $_volume_id_list} |
            Group-Object -AsHashTable VolumeId

        # Get all subnets
        Write-Message -Progress $_cmdlet_name -Status 'Retrieving subnet information.'
        $_subnet_lookup = `
            Get-EC2Subnet -Verbose:$false -Filter @{Name = 'subnet-id'; Values = $_subnet_id_list} |
            Group-Object -AsHashTable SubnetId

        # Get all VPC
        Write-Message -Progress $_cmdlet_name -Status 'Retrieving VPC information.'
        $_vpc_lookup = `
            Get-EC2Vpc -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_vpc_id_list} |
            Group-Object -AsHashTable VpcId

        # Get all ENI
        Write-Message -Progress $_cmdlet_name -Status 'Retrieving ENI information.'
        $_eni_lookup = `
            Get-EC2NetworkInterface -Verbose:$false -Filter @{Name = 'network-interface-id'; Values = $_eni_id_list} |
            Group-Object -AsHashTable NetworkInterfaceId

        # Get all alarms
        Write-Message -Progress $_cmdlet_name -Status 'Retrieving alarm information.'
        $_metric_name_list = `
            Get-CWMetricList -Verbose:$true -Namespace 'AWS/EC2' | Select-Object -Unique -ExpandProperty MetricName
        $_alarm_list = foreach($_metric_name in $_metric_name_list)
        {
            $_alarms_for_this_metric = Get-CWAlarmForMetric -Verbose:$false -MetricName $_metric_name
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught exception.
        $PSCmdlet.ThrowTerminatingError($_)
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
    $_output = $_ec2_list | Select-Object $_select_list | Sort-Object $_sort_list | Select-Object $_project_list

    # Print out the output.
    if ($global:EnableHtmlOutput) {
        $_output | Format-Html -GroupBy $_group_by | Remove-PSStyle
    }
    else {
        $_output | Format-Column -GroupBy $_group_by -PlainText:$_plain_text -NoRowSeparator:$_no_row_separator
    }
}