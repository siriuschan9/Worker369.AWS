using System;
using System.Management.Automation;

namespace Worker369.AWS;

public class HintItem : IComparable, IComparable<HintItem>
{
    public static bool   SortByName { get; set; } = true;

    public string ResourceId   { get; set; }
    public string ResourceName { get; set; }
    public int    Alignment    { get; set; }

    public HintItem(string resourceId, string resourceName, int alignment)
    {
        ResourceId   = resourceId;
        ResourceName = resourceName;
        Alignment    = alignment;
    }

    public int CompareTo(HintItem other)
    {
        if (SortByName)
        {
            var this_no_name = string.IsNullOrEmpty(ResourceName);
            var that_no_name = string.IsNullOrEmpty(other.ResourceName);

            return this_no_name && that_no_name
                ? ResourceId.CompareTo(other.ResourceId)
                : that_no_name
                    ? 1
                    : this_no_name
                        ? -1
                        : ResourceName.CompareTo(other.ResourceName);
        }
        else
            return ResourceId.CompareTo(other.ResourceId);
    }

    public int CompareTo(object other)
    {
        if (other is null)
            return 1;

        if (other is not HintItem that)
            throw new ArgumentException($"Object is not {typeof(HintItem)}");
        else
            return CompareTo(that);
    }

    public override bool Equals(object other)
    {
        if (other is null) return false;

        if (other is not HintItem that) return false;

        return ResourceId == that.ResourceId;
    }

    public override int GetHashCode() => (13 * 23) + ResourceId.GetHashCode();

    public override string ToString()
    {
        var hint_style  = PSStyle.Instance.Dim;
        var reset_style = PSStyle.Instance.Reset;

        if (string.IsNullOrEmpty(ResourceName))
            return ResourceId;
        else
            return string.Format($"{{0,{Alignment}}} {hint_style}| {{1}}{reset_style} ", ResourceId, ResourceName);
    }
}