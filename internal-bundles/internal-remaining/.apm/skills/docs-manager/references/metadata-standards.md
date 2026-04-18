# Metadata Standards Reference

This document defines standard metadata formats and best practices for documentation management.

## Standard Metadata Block Format

All documentation should include a metadata block at the beginning:

```markdown
# [Icon] [Title]

**[Date Field]**: YYYY-MM-DD
**[Audience Field]**: [Target Audience]
**[Tags Field]**: `prefix/value1`, `prefix/value2`, ...
```

### Field Customization

Fields can be customized via configuration:

```json
{
  "metadata_format": {
    "date_field": "最終更新",
    "date_format": "YYYY-MM-DD",
    "audience_field": "対象",
    "tags_field": "タグ"
  }
}
```

Common variations:

- English: `Last Updated`, `Target Audience`, `Tags`
- Japanese: `最終更新`, `対象`, `タグ`
- Custom: Any field names matching your project conventions

## Date Field

### Format

ISO 8601 date format is recommended: `YYYY-MM-DD`

Examples:

- `2025-10-21`
- `2026-01-15`

### Update Policy

- Update on every significant content change
- Flag documents not updated in 6+ months
- Maintain update history section for major changes

### Configurable Update Frequency

Different documents may have different update requirements:

```json
{
  "custom_rules": {
    "update_frequency": {
      "README.md": "quarterly",
      "API.md": "monthly",
      "CHANGELOG.md": "weekly"
    }
  }
}
```

Frequency options:

- `weekly` - Updated every week
- `monthly` - Monthly updates required
- `quarterly` - Quarterly review
- `yearly` - Annual review

## Audience Field

### Purpose

Specify the target readers for the document.

### Common Audiences

### Generic Projects

- Developer
- User
- Contributor
- Maintainer
- Beginner
- Advanced

### Specialized Projects

- Operations/Ops
- SRE
- System Admin
- Architect
- Internal
- External

### Format

Multiple audiences can be specified:

- Comma-separated: `開発者、運用担当者`
- Slash-separated: `Developer/User`
- Hyphenated: `開発者・上級者`

## Tags Field

### Tag Structure

Tags use prefix notation: `prefix/value`

### Common Tag Prefixes

### Universal Prefixes

- `category/` - Document category
- `audience/` - Target reader type
- `environment/` - Environment context

### Project-Specific Prefixes

- `tool/` - Specific tool or technology
- `layer/` - Architecture layer
- `priority/` - Priority level
- `status/` - Document status

### Tag Separator

Two standard formats:

### Comma-Separated

```markdown
**タグ**: `category/guide`, `audience/developer`, `environment/production`
```

### Space-Separated

```markdown
**タグ**: `category/guide` `audience/developer` `environment/production`
```

Configure via:

```json
{
  "tag_separator": ", " // or " " for space-separated
}
```

### Minimum Tag Requirements

All documents should have at minimum:

- 1 `category/` tag
- 1 `audience/` tag

Additional required tags depend on project configuration:

```json
{
  "required_tags": ["category/", "audience/", "environment/"]
}
```

### Tag Vocabulary

Define allowed tag values to ensure consistency:

```json
{
  "tag_vocabulary": {
    "category/": ["documentation", "guide", "reference", "api", "tutorial"],
    "audience/": ["developer", "user", "contributor"]
  }
}
```

Unknown tags should be flagged for review.

## Document Icons

Standard emoji icons for document types:

### Documentation Types

- 📚 Documentation/Guidelines
- 📝 Specification/Design
- 📖 Reference Manual
- 🎓 Tutorial/Learning

### Project Types

- 🎯 Project Overview
- 🚀 Quick Start/Setup
- 🛠 Development/Implementation
- 🔧 Configuration

### Operational

- 🧪 Testing
- 📦 Release/Deployment
- 🐛 Troubleshooting
- 🤝 Contribution

### Technical

- ⚡ Performance
- 🔐 Security
- 🌐 Network/Infrastructure
- 📊 Metrics/Analysis

### Tool-Specific

- 🐚 Shell/Terminal
- 💻 Editor/IDE
- 🔄 CI/CD
- 🗃️ Database

## Metadata Examples

### Generic Documentation

```markdown
# 📚 Project Documentation

**Last Updated**: 2026-01-15
**Target Audience**: Developer, User
**Tags**: `category/documentation`, `audience/developer`, `audience/user`
```

### API Reference

```markdown
# 📝 API Reference

**Last Updated**: 2026-01-15
**Target Audience**: Developer
**Tags**: `category/api`, `category/reference`, `audience/developer`
```

### Configuration Guide

```markdown
# 🔧 Configuration Guide

**Last Updated**: 2026-01-15
**Target Audience**: System Admin, Developer
**Tags**: `category/configuration`, `audience/system-admin`, `audience/developer`, `environment/production`
```

### Troubleshooting

```markdown
# 🐛 Troubleshooting Guide

**Last Updated**: 2026-01-15
**Target Audience**: Operations, Developer
**Tags**: `category/operations`, `category/guide`, `audience/operations`, `audience/developer`
```

## Validation Rules

### Required Field Validation

1. All required fields must be present
2. Date must match configured format
3. Audience must be non-empty
4. Tags must include all required prefixes

### Date Validation

- Must be in ISO 8601 format (YYYY-MM-DD)
- Should not be in the future
- Warn if > 6 months old (configurable threshold)

### Tag Validation

- All required tag prefixes must be present
- Tag values must match vocabulary (if configured)
- Tag separator must match configuration
- Each tag must use `prefix/value` format

### Completeness Score

Calculate metadata completeness:

- Date field present: 25%
- Date format valid: 10%
- Date recent (< 6 months): 10%
- Audience field present: 20%
- All required tags present: 25%
- Tags match vocabulary: 10%

Total: 100% = Complete metadata

## Best Practices

### Consistency

- Use same field names across all documents
- Follow project tag separator convention
- Maintain tag vocabulary consistency

### Maintenance

- Update date on every content change
- Review metadata quarterly
- Validate tags against vocabulary
- Clean up deprecated tags

### Accessibility

- Use clear audience specifications
- Include appropriate icons
- Add relevant tags for discoverability
- Document special requirements

### Scalability

- Start with minimal tags, expand as needed
- Document tag additions in project guidelines
- Validate new tags before widespread use
- Review tag vocabulary annually

## Configuration Integration

### Loading Metadata Configuration

```json
{
  "metadata_format": {
    "date_field": "最終更新",
    "date_format": "YYYY-MM-DD",
    "audience_field": "対象",
    "tags_field": "タグ"
  },
  "required_tags": ["category/", "audience/"],
  "tag_separator": ", ",
  "tag_vocabulary": {
    "category/": ["documentation", "guide", "api"],
    "audience/": ["developer", "user", "contributor"]
  }
}
```

### Applying Custom Standards

1. Define metadata format in configuration
2. Specify required and optional tags
3. Provide tag vocabulary for validation
4. Set tag separator convention
5. Configure update frequency requirements

### Extending Standards

To add project-specific requirements:

1. Add new tag prefix to `required_tags` or `optional_tags`
2. Define vocabulary in `tag_vocabulary`
3. Document usage in project guidelines
4. Update validation rules if needed

## Migration Guide

### From Unstructured to Structured

1. Identify existing metadata patterns
2. Map to standard format
3. Create configuration matching current usage
4. Gradually add missing metadata
5. Validate all documents
6. Update project guidelines

### Changing Metadata Format

1. Document new format requirements
2. Update configuration file
3. Run validation to identify affected documents
4. Batch update metadata blocks
5. Verify consistency
6. Update documentation templates
