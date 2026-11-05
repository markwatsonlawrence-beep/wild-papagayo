WILD PAPAGAYO — WILD ENGINE 3.0 CORE

FILES TO REPLACE ON YOUR LOCAL PROJECT
1. blog-generator.ps1
2. blog-data.json

FILES GENERATED WHEN YOU RUN THE GENERATOR
- blog/*.html
- sitemap.xml
- rss.xml
- wild-engine-report.txt

NORMAL WORKFLOW
1. Add or edit an article in blog-data.json.
2. Add its images to /images/.
3. Run from the site root:
   .\blog-generator.ps1
4. Review wild-engine-report.txt.
5. Upload the generated blog pages, sitemap.xml and rss.xml.

NEW OPTIONAL ARTICLE FIELDS
- related_tags: connects articles automatically.
- internal_links: shows curated links to tours, transportation or other pages.
- iso_date: use YYYY-MM-DD for structured data.

IMPORTANT
Keep a backup before replacing files. The generator does not require every article
to contain the new optional fields.
