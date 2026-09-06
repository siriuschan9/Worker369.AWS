function Show-Ec2
{
    [CmdletBinding()]
    [Alias('ec2_show')]
    param (
        [Parameter(Position = 0)]
        [ValidateSet('Default', 'Network', 'Platform', 'Security', 'Sizing', 'Status', 'StorageSummary', 'StorageDetail')]
        [string]
        $View = 'Default',

        [Amazon.EC2.Model.Filter[]]
        $Filter,

        [ValidateSet('State', 'Vpc', $null)]
        [string]
        $GroupBy = 'Vpc',

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
            'InstanceId', 'Name', 'AvailabilityZone', 'Device', 'Eni', 'EniSubnet',
            'EniPrivateIp', 'EniPublicIp', 'EniIpv6Address'
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
        StorageSummary = @(
            'InstanceId', 'Name', 'RootVolume', 'RootDeviceName', 'AttachedVolumes', 'TotalStorage'
        )
        StorageDetail = @(
            'InstanceId', 'Name', 'DeviceName', 'Volume', 'VolumeEncryptionKey', 'VolumeDelOnTerm', 'VolumeSize'
        )
    }

    # Hashtable for Select-Object.
    $_select_definition = @{
        AlarmStatus = {

        }
        Architecture = {
            $_.Architecture
        }
        AvailabilityZone = {
            $_subnet_lookup[$_.SubnetId].AvailabilityZone
        }
        AttachedVolumes = {
            $_.BlockDeviceMappings.Count
        }
        CpuCredits = {
            $_credit_lookup[$_.InstanceId].CpuCredits
        }
        CurrentInstanceBootMode = {
            $_.CurrentInstanceBootMode
        }
        Device = {
            $_sort_expr = @{Expression = {$_.Attachment.DeviceIndex}}
            $_map_expr  = { $_.Attachment.DeviceIndex }

            $_.NetworkInterfaces | Sort-Object $_sort_expr | ForEach-Object $_map_expr
        }
        DeviceName = {
            $_root_device_name = $_.RootDeviceName
            $_.BlockDeviceMappings | ForEach-Object {
                $_device_name = $_.DeviceName
                "$($_device_name -eq $_root_device_name ? '[ R ]' : '[   ]') $($_device_name)"
            }
        }
        Eni = {
            $_.NetworkInterfaces | ForEach-Object {$_eni_lookup[$_.NetworkInterfaceId]} |
            Get-ResourceString -IdPropertyName 'NetworkInterfaceId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        EniIpv6Address = {
            # Example:
            #   2406:da18:373:cc82::df3e [+1 more]
            #   2406:da18:373:cc82::1    [+1 more]

            # Instead of piping out, prepare an array to store display lines first.
            $_display_items = @()
            $_.NetworkInterfaces | ForEach-Object {
                $_num_additional_ip = [Math]::Max($_.Ipv6Addresses.Count - 1, 0)
                $_display_items += [PSCustomObject]@{
                    Left  = "$($_eni_lookup[$_.NetworkInterfaceId].Ipv6Address)"
                    Right = $_num_additional_ip -gt 0 ? "[+$($_num_additional_ip) more]" : ''
                }
            }
            # We need the maximum length of each substring to align the left and right portion.
            $_left_max_length = `
                $_display_items.Left | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum
            $_right_max_length = `
                $_display_items.Right | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum

            # Return the aligned display lines.
            $_display_items | ForEach-Object {
                "{0, -$_left_max_length} {1, $_right_max_length}" -f $_.Left, $_.Right
            }
        }
        EniPrivateIp = {
            # Example:
            #   10.3.130.20 [+1 more]
            #   10.3.2.114  [+1 more]

            # Instead of piping out, prepare an array to store display lines first.
            $_display_items = @()
            $_.NetworkInterfaces | ForEach-Object {
                $_num_additional_ip = [Math]::Max($_.PrivateIpAddresses.Count - 1, 0)
                $_display_items += [PSCustomObject]@{
                    Left  = "$($_eni_lookup[$_.NetworkInterfaceId].PrivateIpAddress)"
                    Right = $_num_additional_ip -gt 0 ? "[+$($_num_additional_ip) more]" : ''
                }
            }
            # We need the maximum length of each substring to align the left and right portion.
            $_left_max_length = `
                $_display_items.Left | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum
            $_right_max_length = `
                $_display_items.Right | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum

            # Return the aligned display lines.
            $_display_items | ForEach-Object {
                "{0, -$_left_max_length} {1, $_right_max_length}" -f $_.Left, $_.Right
            }
        }
        EniPublicIp = {
            # Example:
            #   10.3.130.20 [+1 more]
            #   10.3.2.114  [+1 more]

            # Instead of piping out, prepare an array to store display lines first.
            $_display_items = @()
            $_.NetworkInterfaces | ForEach-Object {
                $_eni = $_eni_lookup[$_.NetworkInterfaceId]

                $_num_additional_ip = `
                    [Math]::Max(($_eni.PrivateIpAddresses | Select-Object -ExpandProperty Association).Count - 1, 0)

                $_display_items += [PSCustomObject]@{
                    Left  = "$($_eni.PrivateIpAddresses.Association[0].PublicIp)"
                    Right = $_num_additional_ip -gt 0 ? "[+$($_num_additional_ip) more]" : ''
                }
            }
            # We need the maximum length of each substring to align the left and right portion.
            $_left_max_length = `
                $_display_items.Left | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum
            $_right_max_length = `
                $_display_items.Right | Measure-Object -Property Length -Maximum | Select-Object -ExpandProperty Maximum

            # Return the aligned display lines.
            $_display_items | ForEach-Object {
                "{0, -$_left_max_length} {1, $_right_max_length}" -f $_.Left, $_.Right
            }
        }
        EniSubnet = {
            $_.NetworkInterfaces | ForEach-Object {
                $_eni = $_eni_lookup[$_.NetworkInterfaceId]
                $_subnet_lookup[$_eni.SubnetId] |
                Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
        }
        ImageId = {
            $_.ImageId
        }
        ImageName = {
            Get-EC2Image -Verbose:$false -ImageId $_.ImageId -Select Images.Name
        }
        InstanceId = {
            $_.InstanceId
        }
        InstanceProfile = {
            $_.IamInstanceProfile.Arn -replace '^arn:aws:iam::\d{12}:instance-profile\/'
        }
        InstanceStatus = {
            $_status_lookup[$_.InstanceId].Status.Status
        }
        InstanceType = {
            $_.InstanceType
        }
        Ipv6Address= {
            $_.Ipv6Address
        }
        KeyName = {
            $_.KeyName
        }
        Memory = {
            $_type_lookup[$_.InstanceType].NetworkInfo.NetworkPerformance
        }
        Name = {
            $_.Tags | Where-Object Key -eq 'Name' | Select-Object -ExpandProperty Value
        }
        NetworkPerformance = {
            $_type_lookup[$_.InstanceType].NetworkInfo.NetworkPerformance
        }
        PlatformDetails = {
            $_.PlatformDetails
        }
        PrivateIpAddress = {
            $_.PrivateIpAddress
        }
        PublicIpAddress = {
            $_.PublicIpAddress
        }
        RootDeviceName = {
            $_.RootDeviceName
        }
        SecurityGroups = {
            $_.SecurityGroups | ForEach-Object {
                $_sg_lookup[$_.GroupId] |
                Get-ResourceString -PlainText:$_plain_text -IdPropertyName 'GroupId' -TagPropertyName 'Tags'
            }
        }
        State = {
            $_.State.Name.Value
        }
        Subnet = {
            $_subnet_lookup[$_.SubnetId] |
            Get-ResourceString -IdPropertyName 'SubnetId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        SystemStatus = {
            $_status_lookup[$_.InstanceId].SystemStatus.Status
        }
        VCpu = {
            $_type_lookup[$_.InstanceType].VCpuInfo.DefaultVCpus
        }
        Vpc = {
            $_vpc_lookup[$_.VpcId] |
            Get-ResourceString -IdPropertyName 'VpcId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        RootVolume = {
            $_root_device_name = $_.RootDeviceName
            $_root_volume_id = ($_.BlockDeviceMappings | Where-object {$_.DeviceName -eq $_root_device_name}).Ebs.VolumeId
            $_root_volume = $_ebs_lookup[$_root_volume_id]
            $_root_volume | Get-ResourceString -IdPropertyName 'VolumeId' -TagPropertyName 'Tags' -PlainText:$_plain_text
        }
        TotalStorage = {
            $_total = 0
            $_.BlockDeviceMappings.Ebs.ForEach({
                $_volume  = $_ebs_lookup[$_.VolumeId]
                $_total  += $_volume.Size
            })
            $_total * $_gib | New-ByteInfo
        }
        Volume = {
            $_.BlockDeviceMappings | ForEach-Object {
                $_ebs_lookup[$_.Ebs.VolumeId] |
                Get-ResourceString -IdPropertyName 'VolumeId' -TagPropertyName 'Tags' -PlainText:$_plain_text
            }
        }
        VolumeSize = {
            $_.BlockDeviceMappings | ForEach-Object {
                $_ebs_lookup[$_.Ebs.VolumeId].Size * $_gib | New-ByteInfo
            }
        }
        VolumeDelOnTerm = {
            $_.BlockDeviceMappings | ForEach-Object {
                New-Checkbox -PlainText:$_plain_text $_.Ebs.DeleteOnTermination
            }
        }
        VolumeEncryptionKey = {
            $_.BlockDeviceMappings | ForEach-Object {
                $_key_id = $_ebs_lookup[$_.Ebs.VolumeId].KmsKeyId -split '/' | Select-Object -Last 1
                New-Checkbox -PlainText:$_plain_text -Description $_key_id $($_key_id -as [bool])
            }
        }
    }

    # Declare hashtables
    $_alarm_lookup  = @{} # Hashtable to lookup cloudwatch alarm by Instance ID
    $_credit_lookup = @{} # Hashtable to lookup instance credit specification
    $_ebs_lookup    = @{} # Hashtable to lookup EBS volume by Volume ID
    $_eni_lookup    = @{} # Hashtable to lookup ENI info by Network Interface ID
    #$_eip_lookup    = @{} # Hashtable to lookup EIP by Private IP Address
    $_status_lookup = @{} # Hashtable to lookup instance status by Instance ID
    $_subnet_lookup = @{} # Hashtable to lookup subnet info by Subnet ID
    $_type_lookup   = @{} # Hashtable to lookup instance type info by Instance Type
    $_vpc_lookup    = @{} # Hashtable to lookup VPC info by VPC ID

    # Gibibyte
    $_gib = 1024 * 1024 * 1024

    try {
        # Get all EC2
        Write-Message -Progress $_cmdlet_name 'Retrieving EC2 information.'
        $_ec2_list           = Get-EC2Instance -Verbose:$false -Select Reservations.Instances -Filter $_filter
        $_instance_id_list   = $_ec2_list.InstanceId
        $_instance_type_list = $_ec2_list.InstanceType | Select-Object -Unique
        $_volume_id_list     = $_ec2_list.BlockDeviceMappings.Ebs.VolumeId | Select-Object -Unique
        $_subnet_id_list     = $_ec2_list.NetworkInterfaces | Select-Object -Unique -ExpandProperty SubnetId
        $_vpc_id_list        = $_ec2_list.VpcId | Select-Object -Unique
        $_eni_id_list        = $_ec2_list.NetworkInterfaces.NetworkInterfaceId | Select-Object -Unique
        $_sg_id_list         = $_ec2_list.SecurityGroups.GroupId | Select-Object -Unique

        # Get all VPC
        Write-Message -Progress $_cmdlet_name 'Retrieving VPC information.'
        $_vpc_lookup = `
            Get-EC2Vpc -Verbose:$false -Filter @{Name = 'vpc-id'; Values = $_vpc_id_list} |
            Group-Object -AsHashTable VpcId

        # Get all subnets
        Write-Message -Progress $_cmdlet_name 'Retrieving subnet information.'
        $_subnet_lookup = `
            Get-EC2Subnet -Verbose:$false -Filter @{Name = 'subnet-id'; Values = $_subnet_id_list} |
            Group-Object -AsHashTable SubnetId

        # Get all ENI
        if ($_view -in @('Network')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving ENI information.'
            $_eni_lookup = `
                Get-EC2NetworkInterface -Verbose:$false -Filter @{Name = 'network-interface-id'; Values = $_eni_id_list} |
                Group-Object -AsHashTable NetworkInterfaceId
        }
        # Get all Security Groups
        if ($_view -in @('Network', 'Security')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving ENI information.'
            $_sg_lookup = `
                Get-EC2SecurityGroup -Verbose:$false -Filter @{Name = 'group-id'; Values = $_sg_id_list} |
                Group-Object -AsHashTable GroupId
        }
        # Get all instances' credit specifications
        if ($_view -in @('Sizing')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving CPU credit information.'
            $_credit_lookup = `
                Get-EC2CreditSpecification -Verbose:$false $_instance_id_list |
                Group-Object -AsHashTable InstanceId
        }
        # Get all instance types
        if ($_view -in @('Sizing')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving instance type information.'
            $_type_lookup = `
                Get-EC2InstanceType -Verbose:$false -Filter @{Name = 'instance-type'; Values = $_instance_type_list} |
                Group-Object -AsHashTable InstanceType
        }
        # Get all instances' statuses
        if ($_view -in @('Status')) {
            Write-Message -Progress $_cmdlet_name 'Retrieving status information.'
            $_status_lookup = `
                Get-EC2InstanceStatus -Verbose:$false $_instance_id_list |
                Group-Object -AsHashTable InstanceId
        }
        if ($_view -in @('StorageDetail', 'StorageSummary')) {
            # Get all EBS
            Write-Message -Progress $_cmdlet_name 'Retrieving EBS information.'
            $_ebs_lookup = `
                Get-EC2Volume -Verbose:$false -Filter @{Name = 'volume-id'; Values = $_volume_id_list} |
                Group-Object -AsHashTable VolumeId
        }
        # Get all alarms
        Write-Message -Progress $_cmdlet_name 'Retrieving alarm information.'
        # $_metric_name_list = `
        #     Get-CWMetricList -Verbose:$true -Namespace 'AWS/EC2' | Select-Object -Unique -ExpandProperty MetricName
        # $_alarm_list = foreach($_metric_name in $_metric_name_list)
        # {
        #     $_alarms_for_this_metric = Get-CWAlarmForMetric -Verbose:$false -MetricName $_metric_name
        # }
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
        $_output | Format-Column `
            -AlignRight 'VolumeSize', 'VolumeDelOnTerm' `
            -GroupBy $_group_by `
            -PlainText:$_plain_text `
            -NoRowSeparator:$_no_row_separator
    }
}