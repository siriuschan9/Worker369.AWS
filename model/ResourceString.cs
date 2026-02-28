using System;
using System.Management.Automation;

namespace Worker369.AWS;

public enum ResourceStringFormat
{
    Id,
    Name,
    IdAndName
}

public class ResourceString : IComparable, IComparable<ResourceString>
{
    public static bool   SortByName { get; set; } = true;
    public static string NameStyle  { get; set; } = PSStyle.Instance.Formatting.FeedbackName;

    public ResourceStringFormat Format       { get; set; }
    public string               ResourceId   { get; set; }
    public string               ResourceName { get; set; }
    public bool                 PlainText    { get; set; }

    public ResourceString(
        string resourceId,
        string resourceName,
        ResourceStringFormat format = ResourceStringFormat.IdAndName,
        bool plainText = false)
    {
        ResourceId   = resourceId;
        ResourceName = resourceName;
        Format       = format;
        PlainText    = plainText;
    }

    public int CompareTo(ResourceString other)
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

        if (other is not ResourceString that)
            throw new ArgumentException($"Object is not {typeof(ResourceString)}");
        else
            return CompareTo(that);
    }

    public override bool Equals(object other)
    {
        if (other is null) return false;

        if (other is not ResourceString that) return false;

        return ResourceId == that.ResourceId;
    }

    public override int GetHashCode() => (13 * 23) + ResourceId.GetHashCode();

    public override string ToString()
    {
        var name_style = NameStyle;
        var reset_style = PSStyle.Instance.Reset;

        switch (Format)
        {
            case ResourceStringFormat.Id:
                return ResourceId;
            case ResourceStringFormat.Name:
                return string.IsNullOrEmpty(ResourceName) ? ResourceId : ResourceName;
            case ResourceStringFormat.IdAndName:
                if (PlainText)
                    return string.IsNullOrEmpty(ResourceName)
                        ? ResourceId : $"{ResourceId} [{ResourceName}]";
                else
                    return  string.IsNullOrEmpty(ResourceName)
                        ? ResourceId : $"{ResourceId} {name_style}[{ResourceName}]{reset_style}";
            default:
                return string.Empty;
        }
    }
}