# Disk usage glossary

Background for the [disk space triage](disk-space-triage.md) runbook.
This file has no front matter, so runsheets treats it as a plain document:
it is not in the library tree, and nothing on this page executes.

## File system and mount point

A disk, or a slice of one, is formatted as a **file system** and attached
to the directory tree at a **mount point**. Everything below a mount point
lives on that file system until another mount point takes over.

```bash
df -h /            # the file system mounted at /
mount | head       # what is mounted where
```

## df and du

`df` asks the file system how many blocks are in use. `du` walks a directory
and adds up the sizes of the files it can see. They answer different
questions:

- `df -h /tmp` reports the whole file system that holds `/tmp`, including
  everything outside `/tmp`.
- `du -sh /tmp` reports only what is under `/tmp`, and only what you can
  read.

So `du` coming in well below `df` is normal. A large gap is worth a look.

## Deleted-but-open files

Deleting a file removes its name. The space is freed only when no process
still has the file open. A log file deleted while a server is writing to it
keeps growing, invisible to `du`, until the server is restarted or reopens
its logs.

```bash
lsof +L1           # open files with no remaining name
```

## Inodes

Every file uses one inode. A file system can run out of inodes with plenty
of free blocks, usually from millions of tiny files. `df -i` shows inode
use.

See the [cleanup policy](policies/cleanup-policy.md) for what to do about any of it.
