import Foundation

/// Sets `[theme] name` in a config file without disturbing anything else in it — `ConfigWriter`,
/// which began life as this type, with the theme's one safety rule kept in front of it.
public enum ThemeWriter {

    /// The theme's name is slugified on the way in, so nothing this writes can break the file it
    /// is going into: a slug has no quote, no bracket and no newline in it by construction, which
    /// is a stronger guarantee than escaping and one that only has to hold in one place.
    public static func settingTheme(_ name: String, in toml: String) -> String {
        let slug = Slug.make(name)
        return ConfigWriter.setting("name", to: "\"\(slug)\"", inTable: "theme", of: toml)
    }
}
