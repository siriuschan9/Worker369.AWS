function Show-SsoAssignment
{
    [CmdletBinding()]
    [Alias('sso_assign_show')]
    param (
        [ValidateSet('Default')]
        [string]
        $View = 'Default',

        [ValidateSet('Account', 'User')]
        [string]
        $GroupBy = 'Account',

        [Int[]]
        $Sort,

        [Int[]]
        $Exclude,

        [switch]
        $PlainText,

        [switch]
        $NoRowSeparator
    )

    # For easy pick up.
    $_cmdlet_name = $PSCmdlet.MyInvocation.MyCommand.Name

    # Use snake_case.
    $_view             = $View
    $_group_by         = $GroupBy
    $_sort             = $Sort
    $_exclude          = $Exclude
    $_plain_text       = $PlainText.IsPresent
    $_no_row_separator = $NoRowSeparator.IsPresent

    try {
        # Query the IDC instance. There can only be one instance in a region.
        Write-Message -Progress $_cmdlet_name "Retrieving Identity Center Instance."
        $_instance = Get-SSOADMNInstanceList -Verbose:$false

        if (-not $_instance) { return }

        # Save a reference to the Instance ARN and Store ID.
        $_instance_arn = $_instance.InstanceArn
        $_store_id     = $_instance.IdentityStoreId

        # Query all AWS accounts and put them in a lookup.
        Write-Message -Progress $_cmdlet_name "Retrieving AWS Accounts."
        $_acct_list = Get-ORGAccountList -Verbose:$false
        if (-not $_acct_list) { return }

        # Query all Permission Sets
        Write-Message -Progress $_cmdlet_name "Retrieving Permission Sets."
        $_perm_list = `
            Get-SSOADMNPermissionSetList -Verbose:$false $_instance_arn |
            Get-SSOADMNPermissionSet -Verbose:$false -InstanceArn $_instance_arn
        if (-not $_perm_list) { return }

        # Query all Users
        Write-Message -Progress $_cmdlet_name "Retrieving Users."
        $_user_list = Find-IDSUserList -Verbose:$false -IdentityStoreId $_store_id
        if (-not $_user_list) {return }

        # Query all Groups and put them in a lookup
        Write-Message -Progress $_cmdlet_name "Retrieving Groups."
        $_group_list = (Find-IDSGroupList -Verbose:$false -IdentityStoreId $_store_id) ?? @()

        $_acct_lookup  = ($_acct_list  | Group-Object -AsHashTable Id) ?? @{}
        $_user_lookup  = ($_user_list  | Group-Object -AsHashTable UserId) ?? @{}
        $_group_lookup = ($_group_list | Group-Object -AsHashTable GroupId) ?? @{}
        $_perm_lookup  = ($_perm_list  | Group-Object -AsHashTable PermissionSetArn) ?? @{}

        # user1 -> @(group1, group2, ...)
        $_membership_lookup = [System.Collections.Generic.Dictionary[
            string,
            System.Collections.Generic.List[string]]]::new()

        # Populate membership lookup table.
        Write-Message -Progress $_cmdlet_name "Processing each User's group membership."
        foreach ($_group in $_group_list)
        {
            $_group_members = Get-IDSGroupMembershipList -Verbose:$false `
                -IdentityStoreId $_store_id -GroupId $_group.GroupId

            foreach ($_member in $_group_members)
            {
                $_member_id = $_member.MemberId.UserId

                if (-not $_membership_lookup.ContainsKey(($_member_id))) {
                    $_membership_lookup[$_member_id] = `
                        [System.Collections.Generic.List[string]]::new()
                }
                $_membership_lookup[$_member_id].Add($_group.GroupId)
            }
        }

        Write-Message -Progress $_cmdlet_name "Retrieving Assignments."

        # USER, user_id, acct_id -> perm_set1, perm_set2, ...
        $_user_assignment_lookup = $_user_list | ForEach-Object {
            Get-SSOADMNAccountAssignmentsForPrincipalList -Verbose:$false `
            -InstanceArn $_instance_arn `
            -PrincipalType USER `
            -PrincipalId $_.UserId
        } `
        | Where-Object PrincipalType -eq 'USER' # We need a filter here because the result will return inherited groups.
        | Group-Object -AsHashTable -AsString PrincipalType, PrincipalId, AccountId

        # GROUP, group_id, acc_id -> perm_set1, perm_set2, ...
        $_group_assignment_lookup = $_group_list | ForEach-Object {
            Get-SSOADMNAccountAssignmentsForPrincipalList -Verbose:$false `
            -InstanceArn $_instance_arn `
            -PrincipalType GROUP `
            -PrincipalId $_.GroupId
        } | Group-Object -AsHashTable -AsString PrincipalType, PrincipalId, AccountId
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
                # Enclose with asterisk to help us identity direct assignment.
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

    $_select_definition = @{
        User = {
            $_user = $_user_lookup[$_.UserId]
            $_user.UserName
        }
        Account = {
            $_acct = $_acct_lookup[$_.AccountId]
            $_acct | Get-ResourceString -IdPropertyName Id -NamePropertyName Name -PlainText:$_plain_text
        }
        PermissionSet = {
            foreach($_perm_arn in $_.PermissionSet)
            {
                $_perm_set = $_perm_lookup[$_perm_arn]
                $_perm_set.Name
            }
        }
        InheritedViaGroup = {
            foreach($_group_id in $_.InheritedViaGroup)
            {
                $_group = $_group_lookup[$_group_id]
                $_group.Displayname
            }
        }
        IsDirectlyAssigned = {
            New-Checkbox -PlainText:$_plain_text $_.IsDirectlyAssigned
        }
    }

    $_view_definition = @{
        Default = @(
            'User', 'Account', 'PermissionSet', 'InheritedViaGroup', 'IsDirectlyAssigned'
        )
    }

    # Apply default sort order.
    if (
        -not $PSBoundParameters.Keys.Contains('Exclude') -and
        -not $PSBoundParameters.Keys.Contains('Sort')
    ) {
        $_sort = @(1, 2) # => Sort by User, PermissionSet
    }

    # Manufacture the select list, sort list and project list.
    $_select_list, $_sort_list, $_project_list = Get-QueryDefinition `
        -SelectDefinition $_select_definition `
        -ViewDefinition   $_view_definition `
        -View             $_view `
        -GroupBy          $_group_by `
        -Sort             $_sort `
        -Exclude          $_exclude

    # Print out the results.
    $_result_list                |
    Select-Object $_select_list  |  # Initial columns based on selected view.
    Sort-Object   $_sort_list    |  # Sort before exclude.
    Select-Object $_project_list |  # Takes into account exclued columns.
    Select-Object $_project_list |  # Takes into account exclued columns.
    Format-Column `
        -GroupBy $_group_by `
        -PlainText:$_plain_text `
        -NoRowSeparator:$_no_row_separator
}

<#
| User | Account | PermissionSet | InheritedViaGroup | DirectAssignment |
| ---- | ------- | ------------- | ----------------- | ---------------- |
#>