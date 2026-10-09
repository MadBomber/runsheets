# frozen_string_literal: true

module Runsheets
  module Pages
    # The folder tree in the left pane of the library page. Folders are
    # <details> elements, so they fold without script; the page script adds
    # filtering and a keyboard cursor on top.
    module Tree
      module_function

      def h(value) = Renderer.h(value)

      def pane(library, node, session)
        <<~HTML
          <aside class="rs-sidebar lib-tree" aria-label="Runbook tree">
            <div class="lib-filter">
              #{ICONS[:search]}
              <input type="search" id="lib-filter" placeholder="Filter runbooks" aria-label="Filter runbooks" autocomplete="off" spellcheck="false">
              <kbd>/</kbd>
            </div>
            <nav class="tree" id="lib-tree-nav">
              <ul class="tree-root">
                <li class="tree-folder root#{' active' if node.folder? && node.root?}" data-slug="">
                  <a class="node" href="/library">#{ICONS[:home]}<span class="name">All runbooks</span><span class="tree-mark count">#{library.size}</span></a>
                </li>
                #{children(library.root, node, session)}
              </ul>
            </nav>
            <p class="tree-empty" id="lib-tree-empty" hidden>No runbook matches.</p>
          </aside>
        HTML
      end

      # A folder's folders, then its runbooks.
      def children(folder, selected, session)
        folder.folders.map { folder(it, selected, session) }.join +
          folder.entries.map { runbook(it, selected, session) }.join
      end

      # Open when it holds the selection or the runbook open now; the first
      # level is open anyway so a fresh page shows the shape of the library.
      def folder(folder, selected, session)
        inside = [selected.slug, session&.runbook&.slug].compact
        open   = folder.depth == 1 || selected.slug == folder.slug || inside.any? { it.start_with?("#{folder.slug}/") }
        active = selected.folder? && selected.slug == folder.slug
        <<~HTML
          <li class="tree-folder#{' active' if active}" data-slug="#{h folder.slug}">
            <details#{' open' if open}>
              <summary><span class="twisty">#{ICONS[:chevron]}</span>#{ICONS[:folder]}<a class="name" href="#{h Chooser.href(folder.slug)}" title="#{h folder.slug}">#{h folder.name}</a><span class="tree-mark count">#{folder.size}</span></summary>
              <ul>#{children(folder, selected, session)}</ul>
            </details>
          </li>
        HTML
      end

      def runbook(entry, selected, session)
        state   = Chooser.state_of(entry, session)
        classes = ["tree-runbook", state.to_s]
        classes << "active" if selected.runbook? && selected.slug == entry.slug
        classes << "destructive" if entry.destructive?
        search  = [entry.name, entry.title, *entry.tags, entry.slug].join(" ").downcase
        <<~HTML
          <li class="#{classes.join(' ')}" data-slug="#{h entry.slug}" data-search="#{h search}">
            <a class="node" href="#{h Chooser.href(entry.slug)}" title="#{h entry.slug}">#{entry.single_file? ? ICONS[:file] : ICONS[:book]}<span class="name">#{h entry.title}</span>#{mark(entry, state)}</a>
          </li>
        HTML
      end

      def mark(entry, state)
        case state
        when :broken  then '<span class="tree-mark broken" title="does not load">!</span>'
        when :current then '<span class="tree-mark current" title="open now"><span class="dot"></span></span>'
        else "<span class=\"tree-mark count\" title=\"#{entry.steps} steps\">#{entry.steps}</span>"
        end
      end
    end
  end
end
