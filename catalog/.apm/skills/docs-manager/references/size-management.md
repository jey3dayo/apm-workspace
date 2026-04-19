# Document Size Management Reference

This document provides guidelines for managing documentation size and splitting large documents.

## Size Thresholds

### Configurable Limits

Document size limits are configurable via `.docs-manager-config.json`:

```json
{
  "size_limits": {
    "ideal": 300,
    "acceptable": 500,
    "warning": 1000,
    "maximum": 2000
  }
}
```

### Standard Size Categories

### ✅ Ideal

- Quick comprehension
- Easy to scan and navigate
- Optimal for AI processing
- Recommended for most documents

### ⚠️ Acceptable

- Still manageable
- Detailed technical content
- Monitor for growth
- Consider organization improvements

### ⚠️ Large

- Difficult to navigate
- Consider splitting
- Identify logical boundaries
- Plan separation strategy

### 🚫 Too Large

- Must split
- Approaching AI context limits
- Poor user experience
- Maintenance burden

## When to Split Documents

### Indicators for Splitting

1. Size-Based:
   - Document exceeds warning threshold
   - More than 10 major sections
   - Difficulty finding specific content

2. Content-Based:
   - Multiple distinct topics
   - Different target audiences mixed
   - Varying levels of detail

3. Maintenance-Based:
   - Different update frequencies
   - Separate ownership/responsibility
   - Independent versioning needs

4. Usage-Based:
   - Sections frequently referenced independently
   - Different access patterns
   - Selective reading common

## Splitting Strategies

### 1. Topic-Based Splitting

Separate by distinct subject matter:

### Before

```
large-guide.md (1500 lines)
├── Introduction
├── Setup
├── Configuration
├── Advanced Features
├── Troubleshooting
└── API Reference
```

### After

```
README.md (index, 100 lines)
setup-guide.md (300 lines)
configuration-guide.md (400 lines)
advanced-features.md (350 lines)
troubleshooting.md (250 lines)
api-reference.md (450 lines)
```

### 2. Audience-Based Splitting

Separate by target reader:

### Before

```
documentation.md (1200 lines)
├── User Guide
├── Developer Guide
├── Admin Guide
```

### After

```
README.md (index, 50 lines)
user-guide.md (400 lines)
developer-guide.md (500 lines)
admin-guide.md (300 lines)
```

### 3. Detail-Level Splitting

Separate overview from detailed content:

### Before

```
architecture.md (1400 lines)
├── High-Level Overview
├── Component Details
├── API Specifications
├── Implementation Examples
```

### After

```
architecture-overview.md (300 lines)
components/
  ├── component-a.md (250 lines)
  ├── component-b.md (300 lines)
  └── component-c.md (200 lines)
api-spec.md (400 lines)
examples.md (300 lines)
```

### 4. Phase-Based Splitting

Separate by workflow or lifecycle:

### Before

```
complete-guide.md (1600 lines)
├── Getting Started
├── Development
├── Testing
├── Deployment
├── Operations
```

### After

```
README.md (index, 100 lines)
getting-started.md (300 lines)
development.md (400 lines)
testing.md (350 lines)
deployment.md (300 lines)
operations.md (400 lines)
```

## Maintaining Cross-References

### Creating Index Documents

Use main document as navigation hub:

```markdown
# Project Documentation

## Quick Links

- [Getting Started](getting-started.md) - Setup and first steps
- [User Guide](user-guide.md) - Daily usage and features
- [Developer Guide](developer-guide.md) - Contributing and development
- [API Reference](api-reference.md) - Complete API documentation

## Document Structure

### For Users

1. Start with [Getting Started](getting-started.md)
2. Learn features in [User Guide](user-guide.md)
3. Troubleshoot with [FAQ](faq.md)

### For Developers

1. Review [Architecture](architecture.md)
2. Follow [Developer Guide](developer-guide.md)
3. Reference [API Docs](api-reference.md)
```

### Internal Cross-References

Link between split documents:

```markdown
## Configuration

See [Configuration Guide](configuration-guide.md) for detailed setup options.

For advanced configuration patterns, refer to:

- [Environment Variables](configuration-guide.md#environment-variables)
- [Security Settings](configuration-guide.md#security)
- [Performance Tuning](advanced-features.md#performance)
```

### Breadcrumb Navigation

Add navigation aids:

```markdown
# Advanced Features

**Navigation**: [Home](README.md) > [User Guide](user-guide.md) > Advanced Features

**Related Documents**:

- [Configuration Guide](configuration-guide.md) - Basic configuration
- [API Reference](api-reference.md) - API details
- [Troubleshooting](troubleshooting.md) - Common issues
```

## Directory Structure

### Flat Structure

For simple projects (< 10 documents):

```
docs/
├── README.md
├── getting-started.md
├── user-guide.md
├── api-reference.md
└── troubleshooting.md
```

### Categorized Structure

For medium projects (10-30 documents):

```
docs/
├── README.md
├── guides/
│   ├── getting-started.md
│   ├── user-guide.md
│   └── developer-guide.md
├── reference/
│   ├── api.md
│   ├── cli.md
│   └── configuration.md
└── operations/
    ├── deployment.md
    ├── monitoring.md
    └── troubleshooting.md
```

### Hierarchical Structure

For large projects (> 30 documents):

```
docs/
├── README.md
├── overview/
│   ├── introduction.md
│   ├── architecture.md
│   └── concepts.md
├── guides/
│   ├── getting-started/
│   │   ├── installation.md
│   │   ├── quick-start.md
│   │   └── first-project.md
│   ├── user-guide/
│   │   ├── basic-usage.md
│   │   ├── advanced-features.md
│   │   └── best-practices.md
│   └── developer-guide/
│       ├── setup.md
│       ├── development.md
│       └── testing.md
├── reference/
│   ├── api/
│   ├── cli/
│   └── configuration/
└── operations/
    ├── deployment/
    ├── monitoring/
    └── troubleshooting/
```

## Progressive Disclosure

### Layered Information Architecture

Structure content in layers of increasing detail:

### Layer 1: Overview

- High-level purpose
- Key concepts
- Quick start
- Links to detailed docs

### Layer 2: User Guide

- Common use cases
- Step-by-step instructions
- Basic troubleshooting
- Links to reference docs

### Layer 3: Reference

- Complete API documentation
- All configuration options
- Detailed specifications
- Advanced topics

### Layer 4: Deep Dive

- Implementation details
- Architecture decisions
- Performance tuning
- Edge cases

### Example: Progressive API Documentation

### api-overview.md

```markdown
# API Overview

Quick introduction to API concepts and basic usage.

For complete API reference, see:

- [Authentication API](api/authentication.md)
- [Data API](api/data.md)
- [Configuration API](api/configuration.md)
```

### api/authentication.md

Detailed authentication endpoints, parameters, examples.

### api/authentication-advanced.md

OAuth flows, custom authentication, security considerations.

## Splitting Checklist

Before splitting a document:

- [ ] Identify logical section boundaries
- [ ] Determine splitting strategy (topic/audience/detail/phase)
- [ ] Plan directory structure
- [ ] Create index/overview document
- [ ] Update metadata in all documents
- [ ] Add cross-references between documents
- [ ] Update configuration if needed
- [ ] Validate all internal links
- [ ] Test navigation flow
- [ ] Update any external references

After splitting:

- [ ] Run link validation
- [ ] Verify all documents have metadata
- [ ] Check size of new documents
- [ ] Ensure consistent formatting
- [ ] Update project documentation index
- [ ] Notify team of structure changes

## Size Monitoring

### Regular Checks

Monitor document size regularly:

```bash
# Check all document sizes
find docs -name "*.md" -exec wc -l {} + | sort -n

# Find documents exceeding threshold
find docs -name "*.md" -exec wc -l {} + | awk '$1 > 1000'
```

### Automated Tracking

Configure docs-manager to report:

- Documents exceeding size thresholds
- Growth rate over time
- Candidates for splitting
- Size distribution across documentation

### Size Trends

Track document growth:

```json
{
  "size_limits": {
    "ideal": 300,
    "acceptable": 500,
    "warning": 1000,
    "maximum": 2000
  },
  "size_tracking": {
    "enabled": true,
    "alert_threshold": 0.8,
    "growth_rate_warning": "20%"
  }
}
```

## Best Practices

### Before Splitting

1. Identify Natural Boundaries: Look for logical section divisions
2. Consider Usage Patterns: How users access the content
3. Plan Navigation: Design clear navigation structure
4. Preserve Context: Maintain relationships between split sections

### During Splitting

1. Create Index First: Build navigation hub
2. Split One Section at a Time: Incremental approach
3. Update Cross-References: Fix links as you go
4. Test Navigation: Verify user can find content

### After Splitting

1. Validate Links: Ensure all references work
2. Check Metadata: Verify all documents have proper metadata
3. Update Documentation: Reflect new structure
4. Monitor Feedback: Gather user input on new organization

### Maintenance

1. Regular Reviews: Quarterly size checks
2. Growth Monitoring: Track document expansion
3. User Feedback: Listen to navigation difficulties
4. Continuous Improvement: Refine structure as needed

## Common Pitfalls

### Over-Splitting

### Problem

### Solution

- Aim for 300-500 line documents
- Combine closely related topics
- Use strong navigation

### Under-Splitting

### Problem

### Solution

- Be more aggressive with splitting
- Create more granular topics
- Use progressive disclosure

### Poor Navigation

### Problem

### Solution

- Create clear index documents
- Add breadcrumbs
- Provide search functionality
- Include cross-references

### Broken Links

### Problem

### Solution

- Use link validation tools
- Update all references systematically
- Test thoroughly after splitting
- Maintain redirect map if needed

## Tools and Automation

### Size Checking

```bash
# docs-manager size report
# (example command - actual implementation varies)
docs-manager check-sizes --threshold 1000 --report
```

### Splitting Assistance

```bash
# Suggest split points
docs-manager suggest-splits large-doc.md

# Generate index from directory
docs-manager generate-index docs/
```

### Link Validation

```bash
# Validate all links after split
markdown-link-check docs/**/*.md
```

### Configuration

```json
{
  "size_limits": {
    "ideal": 300,
    "acceptable": 500,
    "warning": 1000,
    "maximum": 2000
  },
  "auto_split_suggestions": true,
  "split_strategy": "topic-based"
}
```
