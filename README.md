**English** · [中文](README.zh-CN.md) · [日本語](README.ja.md)

# nook

nook is a local media management tool (Android) for personal collectors. It reaches the shared folders on your PC or NAS over SMB and organizes the videos, images, and assorted collectibles scattered across them into whatever structure you, the collector, choose to give them. nook doesn't play anything itself — tap a work and it hands off to an external player on your phone (such as MX Player).

The word "nook" means a small, quiet, private corner — the kind of place a collector might set aside for the things they treasure. That's where the project's name comes from.

## The problem it solves

A longtime collector tends to accumulate a lot of digital things they love: some are videos, some images, some text. They come from all over, in every format, and piled together they're a mess — hard to sort, hard to enjoy. None of the existing tools really fits:

- **Gallery, VLC (image / video players):** they can only open and play things one at a time. "Management" isn't even on the table. Faced with hundreds or thousands of items of every kind, they're helpless.

- **Solid Explorer, MT Manager (file managers):** fine at managing the files themselves, but not built for a collector. They only know files and folders — all you ever see is a long list of filenames, and there's no way to attach anything to a piece (who is this, how much do I like it, when did I get it). Organizing a collection this way is a chore, and "enjoying" it is out of reach.

- **Jellyfin, Fladder (media libraries / scrapers; Fladder is a Jellyfin-style media-library client):** these go to the opposite extreme. They're built for public content like movies and TV, and lean on the internet to fetch posters, synopses, cast lists, and so on. For niche or personal collections they're both a poor fit and overkill — most niche works don't need all that metadata, and these tools won't let you turn it off. Worse, they'll happily pull posters and other files down from online databases and dump them into your folders, leaving the whole place in disarray.

On one side, players that do too little and can only play. On the other, media libraries that are too heavy and dirty up your folders. For someone who's both a collector at heart and particular about tidiness and order, neither end works. nook is meant to fill that gap in the middle: one tool for managing, displaying, and playing (via an external player) — clean, well-behaved, and concerned only with the collection itself. It deliberately doesn't try to be a general-purpose manager for all your files.

## Design

### Two kinds of shared folder

First and foremost, nook is a browser for SMB shared folders: enter your PC's or NAS's address and credentials on the connection page, and it lists the shared folders there (a _share_ — the root of one collection library), which you can step into and browse.

But nook treats a share in one of two ways, depending on whether the share's root contains a file named `_styles.json`:

- **A plain share** (no `_styles.json`): nook makes no assumptions and simply lets you browse folders and files — much like a file manager. This mode suits a library that hasn't taken shape yet.
- **A styled share** (has `_styles.json`): nook takes it to be a collection already organized by the rules below, and lays it out according to the structure you've defined.

This is decided automatically when you open a share; there's nothing to toggle. What follows describes the structure _inside_ a styled share — and that structure isn't baked into the app. It's determined by how the folders are arranged and by a few convention files; the app only reads and presents it. This is how the author happens to organize their own collection; if you can code, you're free to build on it and swap in whatever scheme you prefer.

### Start with style

When the author picks up something to collect, the first instinct is to file it by _style_. So the very top level in nook isn't time, and isn't type — it's **style**.

How you divide styles is entirely up to you — they can be concrete or quite abstract. You might use Jung's twelve archetypes (Innocent, Explorer, …), or the Major Arcana of the tarot (The Fool, The Magician, …). Styles can also be gathered into groups, and the UI shows different groups separated from one another.

Which folders count as top-level styles, and how they're grouped, is recorded in `_styles.json` at the root:

```json
{
  "styles1": {
    "name": "Jung's Twelve Archetypes Theory",
    "styles": ["Innocent", "Explorer", "Sage"]
  },
  "styles2": {
    "name": "Tarot Major Arcana",
    "styles": ["The Fool", "The Magician"]
  }
}
```

The field names (`styles1`, `styles2`) stand for groups; they aren't shown — they only separate things in the UI. Each entry in an array corresponds to a real folder under the root. Only folders registered here show up as styles.

### Under a style: people

Under a style sit individual subjects. The most common is a **person** — just a subfolder of the styled share, holding that person's works directly:

```
styled share/
└── Person 1/               (a person)
    ├── _cover.jpg          person cover (optional)
    ├── _person.json        metadata (optional)
    ├── .covers/            work covers (optional)
    ├── .gallery/           image gallery (optional)
    ├── personal_vlog.mp4
    └── travel_log.mp4
```

The `_cover.jpg` in a person's folder is that person's cover, so you can tell them apart at a glance while browsing.

### Under a style: groups

But a collection often has **groups** too — a set of people who have both their own works and works they made together. nook tells people and groups apart with a simple convention: a folder that _also contains subfolders_ is treated as a group, and the subfolders inside it are its members; a folder with _no subfolders_ (only work files) is treated as an individual.

```
styled share/
└── The Group/              (a group: it contains member subfolders)
    ├── _cover.jpg          group cover
    ├── Member 1/           (a member — itself a person)
    │   ├── _cover.jpg
    │   ├── _person.json
    │   └── group_mv.mp4    a collaborative work, physically stored here
    └── Member 2/
        ├── _cover.jpg
        └── _person.json    points to the group_mv above via references
```

Groups raise a real problem: one work (say, a film the whole group made together) belongs to several members at once. Copying it into every member's folder wastes space and is a pain to maintain. nook's answer: the work is physically stored under just one member, and the others point to it through _references_. That way there's only ever one copy, yet it shows up under every member it involves — and its info always stays with the member who actually holds the file.

### Works and their info

Under each person are the works themselves (video files). A work can have its own cover, kept in that person's `.covers/` folder and named after the work's filename (e.g. `.covers/group_mv.mp4.jpg`). When showing a work, nook looks, in order, for: a same-named cover under `.covers/` → failing that, the person's `_cover.jpg` → and failing that, a placeholder image. So you can lovingly prepare a cover for every work, or not bother — both are fine.

A work's extra information — date, description, how much you love it, and the references mentioned above — all live in the person's `_person.json`:

```json
{
  "name": "Member 2", // !!! there is no actual "name" field; this note is only a hint — the folder name is the name shown
  "aliases": ["another nickname"],
  "notes": "notes",
  "items": {
    "personal_vlog.mp4": {
      "date": "2023-06-21",
      "description": "description",
      "love": "preferred",
      "lovedAt": "2024-03-15T20:31:00.000"
    }
  },
  "references": ["Style/The Group/Member 1/group_mv.mp4"]
}
```

- The keys under `items` are work filenames; each records that work's date, description, and love level.
- `love` (how much you love it) has three tiers: default (not written), `preferred` (you like it), and `pinnacle` (you treasure it). These aren't just labels — on the **Keep** page, everything marked preferred or pinnacle is gathered together on its own, so you can return to the pieces you treasure most at any time, without digging through the whole library.
- `lovedAt` is when the work was marked as loved; the app writes it automatically, so there's nothing to edit by hand. The Keep page can use it to look back through your favorites by when you saved them.
- Each entry in `references` is the absolute path to a work, written starting from the style level (no share name), used to pull a work from another person's folder into the current one.

Love level, description, and date can all be edited right on your phone after you open a work, and the change is written straight back to `_person.json`. More involved settings (like cross-member references) are done by hand on your computer, editing the file directly. All of this is a direct change to the real files — there's no import/export and no separate database. Your collection's data always stays with the collection, and remains perfectly readable even without nook.

### On demand, never forced

All of those convention files (`_person.json`, `_cover.jpg`, `.covers/`, and so on) are optional. By default nook just shows your folders and files as they are, asking you to prepare nothing in advance; a file is created only when you want to set a cover for a work, mark it as loved, or jot down a description. That restraint is the whole point — it's how nook avoids the scraper's habit of stuffing your directories full of clutter. (Worth noting: the `.covers/` folder is never mistaken for a member of a group.)

Because of this, a collection's root holds, besides the style folders, a few special areas whose names start with `_` (folders whose names start with `_` or `.` are never shown as style content):

```
styled share/
├── _styles.json      the style registry
├── _inbox/           inbox: a holding area for things not yet sorted (optional)
├── _blindbox/        blind box: no structure, everything laid out flat for casual browsing (optional)
├── Style1/           style folder 1 (optional)
├── Style2/           style folder 2 (optional)
└── ...
```

The **blind box** is for things you don't feel like sorting right now, or that you don't especially love but can't bring yourself to delete; the **inbox** is for temporarily piling up whatever hasn't been classified yet.

```
a person/
├── _cover.jpg          person cover (optional)
├── _person.json        metadata (optional)
├── .covers/            work covers (optional)
├── .gallery/           image gallery (optional)
├── personal_vlog.mp4
└── travel_log.mp4
```

And the `.gallery/` folder under each person is that person's **image gallery** — a collection isn't only videos, so images and all sorts of odds and ends can go here. Images are viewed in a dedicated gallery interface; other files can be seen by switching to plain mode.

Finally, every operation nook performs is a move or a rename — it **never deletes a single file**. That's the most basic safety promise it makes to a collector.

### A look at the interface

**Person — work — work details**

<p align="center">
  <img src="docs/person_cover.jpg" width="30%" />
  <img src="docs/work_cover.jpg" width="30%" />
  <img src="docs/work_info.jpg" width="30%" />
</p>

**Login — blind box — Keep (person view)**

<p align="center">
  <img src="docs/login.jpg" width="30%" />
  <img src="docs/blindbox.jpg" width="30%" />
  <img src="docs/keep.jpg" width="30%" />
</p>

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

## Development & building (running from source)

For everyday use, just install the released APK — no compiling needed. The following is for developers who want to run or modify the source.

Environment (Windows, no Android Studio required):

- Git
- OpenJDK
- Flutter SDK (stable)
- Android SDK command-line tools (platform and build-tools)

Once that's set up, the Flutter and Android toolchain entries in `flutter doctor` should both come up as ready.

Running on a phone for debugging:

1. Turn on Developer options and USB debugging on your phone, and connect it to the computer with a cable.
2. From the project root, run:

   ```
   flutter pub get
   flutter run
   ```

3. Make changes as needed.
4. Build the APK:

   ```
   flutter build apk --release
   ```

The output lands at `build/app/outputs/flutter-apk/app-release.apk`.
