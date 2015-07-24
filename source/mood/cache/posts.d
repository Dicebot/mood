module mood.cache.posts;

import std.datetime;
import vibe.core.log;
import mood.cache.core;

struct BlogPost
{
    string md;

    string title;
    string html;

    SysTime created_at;

    string pretty_date() const @property
    {
        return (cast(Date) this.created_at).toSimpleString();
    }

    static BlogPost create(string key, string src)
    {
        import vibe.textfilter.markdown;
        import std.regex, std.string;

        BlogPost entry;
        entry.md   = src;
        entry.html = filterMarkdown(src, MarkdownFlags.backtickCodeBlocks);

        static first_comment = ctRegex!(r"<!--([^-]+)-->");
        auto possible_metadata = src.matchFirst(first_comment);

        if (!possible_metadata.empty)
        {
            auto metadata = strip(possible_metadata[1]);
            parseMetadata(metadata, entry);
        }

        return entry;
    }

    private static void parseMetadata(string src, ref BlogPost dst)
    {
        import std.regex, std.string;

        static key_value = ctRegex!(r"^([^:]+): (.+)$");

        foreach (line; src.splitLines())
        {
            auto pair = line.matchFirst(key_value);
            if (!pair.empty)
            {
                auto key = pair[1];
                auto value = pair[2];

                if (key == "Title")
                    dst.title = value;
                else if (key == "Date")
                    dst.created_at = SysTime.fromISOString(value);
            }
        }
    }
}

struct BlogPosts
{
    import vibe.inet.path : Path;
    import std.algorithm : sort, map;

    private:

        Cache!BlogPost cache;
        immutable(BlogPost)*[] by_date;

    public:

        auto posts_by_url() @property
        {
            return this.cache.entries;
        }

        auto posts_by_date() @property
        {
            return this.by_date;
        }

        ref typeof(this) add(string key, string data) 
        {
            this.cache.replaceWith(this.cache.add(key, data));
            this.reindexCache();
            return this;
        }

        /**
            Scans file system for markdown sources and builds a new cache
            based on that, replacing the current one.

            Params:
                root_path = directory where all .md files are stored
         */
        void loadFromDisk(Path root_path)
        {
            this.cache.replaceWith(this.cache.loadFromDisk(root_path, ".md"));
            this.reindexCache();
        }

    private:

        void reindexCache()
        {
            this.by_date.length = this.cache.entries.length;
            size_t index = 0;
            foreach (key, ref value; this.cache.entries)
            {
                this.by_date[index] = &value;
                ++index;
            }
            sort!((a, b) => a.created_at > b.created_at)(this.by_date);
        }
}

unittest
{
    BlogPosts cache;

    cache.add("/url", "# abcd");
    assert (cache.posts_by_url["/url"].html == "<h1> abcd</h1>\n");

    cache.clear();
    cache.replaceWith(cache.add("/block/1", "# a"));
    cache.replaceWith(cache.add("/block/2", "## b"));
    cache.replaceWith(cache.add("/block/3", "### c"));

    assert (cache.posts_by_url["/block/1"].html == "<h1> a</h1>\n");
    assert (cache.posts_by_url["/block/2"].html == "<h2> b</h2>\n");
    assert (cache.posts_by_url["/block/3"].html == "<h3> c</h3>\n");
}