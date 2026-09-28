<!--
Output template for work-summary. Copy the structure, replace the placeholders, delete
every comment. Omit a section or a group that has no entry. The published example is
https://gist.github.com/web-padawan/dd296fba35ef1906f81505eb3c2cb362

Voice:
- bullets are short lowercase fragments with no final period
- a group lead line ends with a colon
- plain words, no "significantly", "major", "robust", "seamless"
- a number only with its unit, and only when a PR or an issue measured it
- scenarios in Highlights, method names only in the PRs list
-->
Overview of improvements in `<component>` <web component | Flow component> in <Mon-Mon YYYY>.

## Highlights

### Performance

<!-- Only measured gains. Omit the section if no PR measured one. -->
- <what the code does now, in one line>
- <measured result, for example: collapse costs 2 forced layouts instead of up to 12>

### UX value

<!-- Group by outcome. One line per scenario that an application developer or end user sees. -->
<Scenarios that work now>:

- <layout or interaction that was broken, in the words of the user>

<Other fixes>:

- <behavior that is correct now>

<!-- Only when a fix changes shared behavior, and a test or a probe checks the unchanged cases. -->
<Cases that keep working>:

- <layout that already worked and keeps the same result>

Other:

- <feature or API that the work added>

## Issues

Fixed and closed:

- <issue URL> - **BFP**
- <issue URL>

Verified and closed:

<!-- Closed by hand as completed, because earlier work had fixed them. -->
- <issue URL>

## PRs

### Performance

- refactor: [<title without the type prefix>](<PR URL>)

### Fixes

- fix: [<title>](<PR URL>)

### Tests

- test: [<title>](<PR URL>)

### Other

- refactor: [<title>](<PR URL>)
- feat: [<title>](<PR URL>)
- refactor: [<title>](<PR URL>) (<why a shared PR is listed, for example: shared with context-menu>)

### Dev pages

- chore: [<title>](<PR URL>)
