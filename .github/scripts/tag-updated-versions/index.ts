import * as fs from 'fs/promises'
import { join, dirname } from 'path'
import { cwd, env } from 'process'
import { exec as execCallback } from 'child_process'
import { promisify } from 'util'
import * as semver from 'semver'
import conventionalCommitsParser, { Commit } from 'conventional-commits-parser'
import * as core from '@actions/core'
import * as github from '@actions/github'

const exec = promisify(execCallback)
const headSha = env.GITHUB_SHA ?? 'HEAD'
const TAG_PREFIX = 'v'

// Paths to explicitly exclude from triggering a release
// We exclude 'dist' because it is a build artifact, and '.github' to prevent workflow tweaks from cutting releases.
const IGNORED_PATHS = [
  ':(exclude)node_modules',
  ':(exclude)dist',
  ':(exclude)scripts',
  ':(exclude).github',
  ':(exclude).git'
]

async function createRelease (version: string, commits: Commit[]): Promise<null> {
  const tagName = `${TAG_PREFIX}${version}`
  const body = commits
    .map((c) => c.header)
    .filter((h) => h != null)
    .map((h) => `* ${h ?? ''}`)
    .join('\n')

  core.info(`Creating release ${tagName}:`)
  core.info(body)

  try {
    const gh = github.getOctokit(env.GITHUB_TOKEN ?? '')
    const [owner, repo] = env.GITHUB_REPOSITORY?.split('/', 2) ?? ['', '']

    // Create the release (which creates the tag automatically)
    await gh.rest.repos.createRelease({
      owner,
      repo,
      tag_name: tagName,
      name: tagName,
      body,
      draft: false,
      prerelease: false,
      make_latest: 'true',
      target_commitish: headSha
    })
  } catch (error: any) {
    const message: string = error.message ?? 'Unknown error'
    core.setFailed(`Failed to create release for ${tagName}: ${message}`)
  }
  return null
}

function bumpType (commit: Commit): 'major' | 'minor' | 'patch' | null {
  const commitType = commit.type ? commit.type.toLowerCase() : ''
  const header = commit.header ?? ''

  // 1. Major: "!" symbol or BREAKING CHANGE
  if (header.includes('!:') || header.includes('!(')) {
    return 'major'
  }
  if (commit.notes.some((n) => n.title === 'BREAKING CHANGE')) {
    return 'major'
  }

  // 2. Minor: "feat"
  if (['feat', 'feature'].includes(commitType)) {
    return 'minor'
  }

  // 3. Patch: "fix"
  if (['fix'].includes(commitType)) {
    return 'patch'
  }

  return null
}

async function getLatestTag (root: string): Promise<string | null> {
  // Look for tags starting with 'v' (e.g. v1.0.0)
  const ls = await exec(`git tag -l "${TAG_PREFIX}*"`, { cwd: root })
  if (ls.stdout === '') {
    return null
  }

  // Sort by semver to get the highest version
  const tags = ls.stdout.trimEnd().split('\n')
  return semver.rsort(tags)[0]
}

async function getCommits (root: string, latestTag: string | null): Promise<Commit[]> {
  // If no tag exists, look at all history. If tag exists, look from tag to HEAD.
  const range = latestTag ? `${latestTag}...${headSha}` : headSha

  // git log with pathspecs to include root but exclude IGNORED_PATHS
  // " -- . :(exclude)dist ..."
  const pathspec = `. ${IGNORED_PATHS.join(' ')}`
  const cmd = `git log -z --no-decorate --pretty=medium ${range} -- ${pathspec}`

  try {
    const ls = await exec(cmd, { cwd: root })
    if (ls.stdout === '') return []

    return ls.stdout.split('\0').map((c) =>
      conventionalCommitsParser.sync(c.split('\n\n', 2)[1].trim())
    )
  } catch (e) {
    core.warning(`Could not fetch commits: ${e}`)
    return []
  }
}

async function rootDirectory (): Promise<string> {
  let directory = cwd()
  while (true) {
    try {
      await fs.lstat(join(directory, '.git'))
      return directory
    } catch (_) {
      directory = await dirname(directory)
      if (directory === '/' || directory === '.') return cwd()
    }
  }
}

// Main Execution
const root = await rootDirectory()
core.info(`Git root: ${root}`)

const latestTag = await getLatestTag(root)
const currentVersion = latestTag ? semver.clean(latestTag) : '0.0.0'

core.info(`Current version: ${currentVersion}`)

const commits = await getCommits(root, latestTag)

if (commits.length === 0) {
  core.info('No relevant commits found since last tag.')
} else {
  const bumpTypes = commits.map(bumpType)

  let incType: semver.ReleaseType | null = null
  if (bumpTypes.includes('major')) {
    incType = 'major'
  } else if (bumpTypes.includes('minor')) {
    incType = 'minor'
  } else if (bumpTypes.includes('patch')) {
    incType = 'patch'
  }

  if (incType != null && currentVersion) {
    const newVersion = semver.inc(currentVersion, incType)
    if (newVersion) {
      core.info(`Bumping version: ${currentVersion} -> ${newVersion} (${incType})`)
      await createRelease(newVersion, commits)
    }
  } else {
    core.info('Changes detected, but no semantic version triggers (feat/fix/!) found.')
  }
}
