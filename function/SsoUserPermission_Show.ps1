function Show-SsoUserPermission
{
    [CmdletBinding(DefaultParameterSetName = 'AllUSers')]
    [Alias('sso_uperm_show')]
    param (
        [Parameter(ParameterSetName = 'OneUser', Position = 0)]
        [string]
        $Username
    )

    # For easy pick up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name
    $_param_set   = $PSCmdlet.ParameterSetName

    # Use snake_case.
    $_username = $Username

    try{
        # Query the IDC instance. There can only be one instance in a region.
        Write-Message -Progress $_cmdlet_name "Retrieving Identity Center Instance."
        $_instance = Get-SSOADMNInstanceList -Verbose:$false

        if (-not $_instance) { return }

        # Save a reference to the Instance ARN and Store ID.
        $_instance_arn = $_instance.InstanceArn
        $_store_id     = $_instance.IdentityStoreId

        # Query User(s).
        Write-Message -Progress $_cmdlet_name "Retrieving Users."

        if ($_param_set -eq 'AllUsers')
        {
            $_user_list = Find-IDSUserList -Verbose:$false -IdentityStoreId $_store_id
        }
        else
        {
            $_user_id = Get-IDSUserId -Verbose:$false `
                -IdentityStoreId $_store_id `
                -UniqueAttribute_AttributePath 'Username' `
                -UniqueAttribute_AttributeValue $_username

            if (-not $_user_id) { return }

            $_user_list = Get-IDSUser -Verbose:$false -IdentityStoreId $_store_id $_user_id

            [System.Diagnostics.Debug]::Assert($_user_list)
        }
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }

    try {
        # Query all AWS accounts.
        Write-Message -Progress $_cmdlet_name "Retrieving AWS Accounts."

        $_acct_list = Get-ORGAccountList -Verbose:$false

        if (-not $_acct_list) { return }

        # Query all Permission Sets.
        Write-Message -Progress $_cmdlet_name "Retrieving Permission Sets."

        $_perm_list = `
            Get-SSOADMNPermissionSetList -Verbose:$false -InstanceArn $_instance_arn |
            Get-SSOADMNPermissionSet -Verbose:$false -InstanceArn $_instance_arn

        if (-not $_perm_list) { return }

        # Query Groups.
        Write-Message -Progress $_cmdlet_name "Retrieving Groups."

        if ($_param_set -eq 'AllUsers')
        {
            $_group_list = (Find-IDSGroupList -Verbose:$false -IdentityStoreId $_store_id) ?? @()
        }
        else
        {
            $_group_id = Get-IDSGroupMembershipsForMemberList -Verbose:$false -Select GroupMemberships.GroupId `
                -IdentityStoreId $_store_id `
                -MemberId_UserId $_user_list[0].UserId

            if ($_group_id)
            {
                $_group_list = (Get-IDSGroup -IdentityStoreId $_store_id $_group_id) ?? @()
            }
        }

        # Put all of them in hashtables.
        $_acct_lookup  = ($_acct_list  | Group-Object -AsHashTable Id) ?? @{}
        $_user_lookup  = ($_user_list  | Group-Object -AsHashTable UserId) ?? @{}
        #$_group_lookup = ($_group_list | Group-Object -AsHashTable GroupId) ?? @{}
        $_perm_lookup  = ($_perm_list  | Group-Object -AsHashTable PermissionSetArn) ?? @{}

        # user1 -> @(group1, group2, ...)
        $_membership_lookup = [System.Collections.Generic.Dictionary[
            string,
            System.Collections.Generic.List[string]]]::new()

        # Populate membership lookup table.
        Write-Message -Progress $_cmdlet_name "Processing group membership."

        if ($_param_set -eq 'AllUsers')
        {
            foreach ($_group in $_group_list)
            {
                $_group_members = Get-IDSGroupMembershipList -Verbose:$false -IdentityStoreId $_store_id $_group.GroupId

                foreach ($_member in $_group_members)
                {
                    $_member_id = $_member.MemberId.UserId

                    if (-not $_membership_lookup.ContainsKey(($_member_id))) {
                        $_membership_lookup[$_member_id] = [System.Collections.Generic.List[string]]::new()
                    }
                    $_membership_lookup[$_member_id].Add($_group.GroupId)
                }
            }
        }
        else
        {
            $_user = $null
            $_user = $_user_list[0]

            $_membership_lookup[$_user.UserId] = [System.Collections.Generic.List[string]]::new()
            $_membership_lookup[$_user.UserId].AddRange([string[]]($_group_list.GroupId))
        }

        Write-Message -Progress $_cmdlet_name "Retrieving Assignments."

        # USER, user_id, acct_id -> perm_set1, perm_set2, ...
        $_user_assignment_lookup = (
            $_user_list | ForEach-Object {
                Get-SSOADMNAccountAssignmentsForPrincipalList -Verbose:$false `
                    -InstanceArn $_instance_arn `
                    -PrincipalType USER `
                    -PrincipalId $_.UserId
            } `
            | Where-Object PrincipalType -eq 'USER' # Need a filter here because the result returns inherited groups.
            | Group-Object -AsHashTable -AsString PrincipalType, PrincipalId, AccountId
        ) ?? @{}

        # GROUP, group_id, acc_id -> perm_set1, perm_set2, ...
        $_group_assignment_lookup = (
            $_group_list | ForEach-Object {
                Get-SSOADMNAccountAssignmentsForPrincipalList -Verbose:$false `
                    -InstanceArn $_instance_arn `
                    -PrincipalType GROUP `
                    -PrincipalId $_.GroupId
            } | Group-Object -AsHashTable -AsString PrincipalType, PrincipalId, AccountId
        ) ?? @{}
    }
    catch {
        # Remove caught exception emitted into $Error list.
        Pop-ErrorRecord $_

        # Re-throw caught error.
        $PSCmdlet.ThrowTerminatingError($_)
    }
    finally {
        Write-Message -Progress -Complete $_cmdlet_name "Data retrieval done."
    }

    # user_id, acct_id, perm_arn -> group1, group2, ...
    $_inheritance_lookup = [System.Collections.Generic.Dictionary[
        string,
        System.Collections.Generic.HashSet[string]]]::new()

    foreach ($_user in $_user_list)
    {
        # Get direct assignment to each account.
        foreach ($_acct in $_acct_list)
        {
            $_perm_list = $null
            $_perm_list = $_user_assignment_lookup["USER, $($_user.UserId), $($_acct.Id)"]

            foreach ($_perm_set in $_perm_list)
            {
                $_inheritance_key = "$($_user.UserId), $($_acct.Id), $($_perm_set.PermissionSetArn)"

                if (-not $_inheritance_lookup.ContainsKey($_inheritance_key))
                {
                    $_inheritance_lookup[$_inheritance_key] = [System.Collections.Generic.HashSet[string]]::new()
                }
                # Enclose with asterisk to help us identity direct assignment later.
                $_inheritance_lookup[$_inheritance_key].Add("*$($_user.UserId)*") | Out-Null
            }
        }

        # Get indirect assignment to each account.
        foreach ($_membership in $_membership_lookup[$_user.UserId])
        {
            foreach ($_acct in $_acct_list)
            {
                $_perm_list = $null
                $_perm_list = $_group_assignment_lookup["GROUP, $($_membership), $($_acct.Id)"]

                foreach ($_perm_set in $_perm_list)
                {
                    $_inheritance_key = "$($_user.UserId), $($_acct.Id), $($_perm_set.PermissionSetArn)"

                    if (-not $_inheritance_lookup.ContainsKey($_inheritance_key))
                    {
                        $_inheritance_lookup[$_inheritance_key] = `
                            [System.Collections.Generic.HashSet[string]]::new()
                    }
                    $_inheritance_lookup[$_inheritance_key].Add($_membership) | Out-Null
                }
            }
        }
    }

    $_result_list = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($_inheritance_key in $_inheritance_lookup.Keys)
    {
        $_user_id  = $null
        $_acct_id  = $null
        $_perm_arn = $null

        # Extract out the User ID, Account ID, Permission Set ARN from the key.
        $_user_id, $_acct_id, $_perm_arn = $_inheritance_key -split ', '

        # Save a reference to the Inheritance list for easy pick up.
        $_inheritance_list = $_inheritance_lookup[$_inheritance_key]

        # Create a result item and add it to the result list.
        $_result_list.Add([PSCustomObject]@{
            UserId             = $_user_id
            AccountId          = $_acct_id
            PermissionSet      = $_perm_arn
            InheritedViaGroup  = $_inheritance_list | Where-Object {$_ -ne "*$($_user_id)*" }
            IsDirectlyAssigned = $_inheritance_list.Contains("*$($_user_id)*")
        })
    }

    Write-Host

    $_bold      = [System.Management.Automation.PSStyle]::Instance.Bold
    $_underline = [System.Management.Automation.PSStyle]::Instance.Underline
    $_highlight = [System.Management.Automation.PSStyle]::Instance.Formatting.FeedbackName
    $_reset     = [System.Management.Automation.PSStyle]::Instance.Reset

    # Measure the length of account names for alignment later.
    $_width = $_result_list | Select-Object -ExpandProperty AccountId | ForEach-Object {
        $_acct_lookup[$_].Name
    } | Measure-Object -Maximum Length | Select-Object -ExpandProperty Maximum

    # Print out the results.
    $_uid_groups = $_result_list | Group-Object UserId

    foreach ($_uid_group in $_uid_groups)
    {
        $_user = $_user_lookup[$_uid_group.Name]

        Write-Host "- $($_bold)$($_user.UserName)$($_reset)"

        $_acct_groups = $_uid_group.Group | Group-Object AccountId

        foreach ($_acct_group in $_acct_groups)
        {
            $_acct      = $_acct_lookup[$_acct_group.Name]
            $_acct_id   = $_acct.Id.Insert(4, '-').Insert(9, '-')
            $_acct_name = $_acct.Name

            Write-Host -NoNewline ("  |- {0} $($_highlight)[{1, -$_width}]$($_reset) : " -f $_acct_id, $_acct_name)

            foreach ($_assignment in $_acct_group.Group)
            {
                $_perm = $_perm_lookup[$_assignment.PermissionSet]

                if ($_assignment.IsDirectlyAssigned) {
                    Write-Host -NoNewline "$($_underline)$($_perm.Name)$($_reset) "
                }
                else {
                    Write-Host -NoNewline "$($_perm.Name) "
                }
            }; Write-Host
        }; Write-Host
    }
}

Register-ArgumentCompleter -ParameterName 'Username' -CommandName 'Show-SsoUserPermission' -ScriptBlock {

    param(
        $_command_name,
        $_parameter_name,
        $_word_to_complete,
        $_command_ast,
        $_fake_bound_parameters
    )

    $_store_id = Get-SSOADMNInstanceList -Verbose:$false -Select Instances.IdentityStoreId

    if (-not $_store_id) { return }

    Find-IDSUserList -Verbose:$false -Select Users.UserName -IdentityStoreId $_store_id | Where-Object {
        $_ -like "$_word_to_complete*"
    } | ForEach-Object {

        [System.Management.Automation.CompletionResult]::new(
            $_,               # completionText
            $_,               # listItemText
            'ParameterValue', # resultType
            $_                # toolTip
        )
    }
}