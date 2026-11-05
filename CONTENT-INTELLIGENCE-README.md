# Wild Content Intelligence Engine v1.0

## Included

- `content-opportunity-engine.ps1`
- `article-builder.ps1`
- `content-draft-validator.ps1`

## Workflow

1. Discover content opportunities:

```powershell
.\content-opportunity-engine.ps1 -Top 50 -OpenReport
```

2. Open:

```text
knowledge/content/opportunities/content-opportunities.json
```

3. Create a grounded article scaffold:

```powershell
.\article-builder.ps1 -OpportunityId "<opportunity-id>"
```

4. Review the JSON draft in:

```text
knowledge/content/drafts/
```

5. Validate it:

```powershell
.\content-draft-validator.ps1 -Slug "<article-slug>"
```

6. After replacing placeholders and verifying facts, add it to `blog-data.json`:

```powershell
.\article-builder.ps1 -OpportunityId "<opportunity-id>" -PublishDraft -Force
```

7. Generate the HTML:

```powershell
.\blog-generator.ps1
```

## Safety

The builder creates an editorial scaffold. It does not invent current prices, schedules, policies or hotel facts. Human factual review is required before publication.
