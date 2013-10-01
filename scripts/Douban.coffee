class JsonObject
        constructor: (@json) ->
                for key, value of json
                        @[key] = value
                

class Channel extends JsonObject
        appendSongs: (newSongs) ->
                if not newSongs?
                        return
                @songs ?= []
                # TODO: check max size and release
                @songs = @songs.concat(newSongs)
                return
                
        update: (succ, err, action, sid, history) ->
                window.DoubanFM?.doGetSongs(
                        @,
                        action, sid, history,
                        ((json) =>
                                # TODO: append song list instead of replacing
                                @appendSongs(new Song(s) for s in json?.song)
                                succ?(@songs)
                        )
                                ,
                        err
                )

        
class Song extends JsonObject
        # not so logic, it get liked/unliked/booed/skipped
        like: () ->
                window.DoubanFM?.doLike(@)

        unlike: () ->
                window.DoubanFM?.doUnlike(@)
                
        boo: () ->
                window.DoubanFM?.doBoo(@)
                
        skip: () ->
                window.DoubanFM?.doSkip(@)

class User extends JsonObject
        attachAuth: (data) ->
                data["user_id"] = @user_id if @user_id?
                data["token"] = @token if @token?
                data["expire"] = @expire if @expire?

class Service
        constructor: (@proxy) ->

        query: (type, url, data, succ, err) ->
                data['url'] = url
                console.log "#{type} #{url}"
                console.log "Data: "
                console.log data
                $.jsonp({
                        type: type,
                        data: data,
                        url: @proxy + "?callback=?",
                        
                        xhrFields: {
                                withCredentials: false
                        },
                        success: (data) -> succ(data)
                                ,
                        error: (j, status, error) -> err(status, error)
                })

        get: (url, data, succ, err) ->
                @query("GET", url, data, succ, err)

        post: (url, data, succ, err) ->
                @query("POST", url, data, succ, err)
                
proxy_domain = "http://localhost:10080"
#proxy_domain = "https://jsonpwrapper.appspot.com"

window.Service ?= new Service(proxy_domain)

class Player
        constructor: () ->
                @sounds = {}
                # Actions
                @action = {}
                @action.END = "e"
                @action.NONE = "n"
                @action.BOO = "b"
                @action.LIKE = "r"
                @action.UNLIKE = "u"
                @action.SKIP = "s"
                
                @maxHistoryCount = 15
                
                @currentSongIndex = -1
                
                soundManager.setup({
                        url: "SoundManager2/swf/",
                        preferFlash: false,

                        onready: () ->
                                window.T?.echo("Player initialized");
                        ontimeout: () ->
                                window.T?.error("Failed to intialize player. Check your brower's flash setting.")
                });

        bind: (div) ->
                @$ui = $(div)

        onLoading: () ->
                #@$ui.text("Loading.. #{@current.bytesLoaded / @current.bytesTotal * 100}")

        formatTime: (ms) ->
                s = Math.floor(ms / 1000)
                MS = ms - s * 1000
                MM = Math.floor(s / 60)
                SS = s - MM * 60
                return "#{MM}:#{SS}"

        onPlaying: (pos) ->
                barWidth = 30
                # playing progress
                pos = @currentSound.position
                duration = @currentSound.duration
                percent = pos / duration

                # loading progress
                loaded_percent = @currentSound.bytesLoaded / @currentSound.bytesTotal
                ld_bar_count = Math.round(barWidth * loaded_percent)

                
                        
                hl_bar_count = Math.floor(barWidth * percent)
                nm_bar_count = barWidth - hl_bar_count

                delta_bar_count = ld_bar_count - hl_bar_count
                if delta_bar_count < 0
                        delta_bar_count = 0
     
                no_bar_count = nm_bar_count - delta_bar_count
                nm_bar_count = delta_bar_count
                
                hl_format = "[gb;#2ecc71;#000]"
                nm_format = "[gb;#fff;#000]"
                no_format = "[gb;#000;#000]"
                
                left = $.terminal.escape_brackets("[")
                right = $.terminal.escape_brackets("]")
                hl = Array(hl_bar_count).join(">") + "♫"
                nm = Array(nm_bar_count).join("=") + (if no_bar_count > 0 then "☁" else "==")
                nu = Array(no_bar_count + 1).join("-")
                time = "#{@formatTime(pos)}/#{@formatTime(duration)}"
                bar_str = "[#{nm_format}#{left}][#{hl_format}#{hl}][#{nm_format}#{nm}][#{no_format}#{nu}][#{nm_format}#{right} #{time}]"

                bar = $.terminal.format(bar_str)
                @$ui.text("")
                @$ui.append(bar)

        play: (channel) ->
                # if playing then stop
                @stop()
                @startPlay(channel)

        stop: () ->
                @currentSound?.unload()
                @currentSound?.stop()
                        

        startPlay: (channel) ->
                @currentChannel = channel

                # initialize
                @currentSongIndex = -1
                @currentSong = null
                @history = []

                @nextSong(@action.NONE)
        
        getHistory: () ->
                str = "|"
                H = $(@history).map (i, h) ->
                        h.join(":")
                str += H.get().join("|")
                return str
                
        nextSong: (action) ->
                @stop()

                sid = ""
                if @currentSong
                        sid = @currentSong.sid
                        h = [sid, action]
                        # slice to make sure the size 
                        if @history.length > @maxHistoryCount
                                @history = @history[1..]
                        @history.push(h)
                        console.log @getHistory()
                        
                # TODO: record history
                # if not in cache, update
                if (@currentSongIndex + 1 >= @currentChannel.songs.length)
                        # TODO: prompt user that we are updating
                        @currentChannel.update(
                                (songs) => @nextSong(action),
                                () -> #TODO:,
                                action,
                                sid,
                                @getHistory())
                        return # block operation here
                # handle action of previous song
                # action could be booo, finish, skip, null
                if (@currentSongIndex > -1)
                        @currentChannel.update(null, null, action, sid, @getHistory())
                # get next song
                @currentSongIndex++

                # do simple indexing, since when channel is updated, song list is appended
                @doPlay(@currentChannel.songs[@currentSongIndex])
                
        doPlay: (song) ->
                id = song.sid
                url = song.url
                artist = song.artist
                title = song.title
                album = song.albumtitle
                picture = song.picture
                like = song.like != 0
                like_format = if like then "[gb;#f00;#000]" else "[gb;#fff;#000]"
                #window.T.clear()
                window.T.echo "[#{like_format}♥ ][[gb;#e67e22;#000]#{song.artist} - #{song.title} #{song.albumtitle}]"

                @currentSong = song
                @currentSound = @sounds[id]
                window.T.echo("Loading...",
                        {
                                finalize: (div) => @bind(div),
                        })

                @currentSound ?= soundManager.createSound({
                        url: url,
                        autoLoad: true,
                        whileloading: () => @onLoading(),
                        whileplaying: () => @onPlaying(),
                        onload: () -> @.play()
                        onfinish: () => @nextSong(@action.END)
                        # TODO: invoke nextSong when complete
                })
                


        
class DoubanFM
        app_name = "radio_desktop_win"
        version = 100
        domain = "http://www.douban.com"
        login_url = "/j/app/login"
        channel_url = "/j/app/radio/channels"
        song_url = "/j/app/radio/people"

        attachVersion: (data) ->
                data["app_name"] = app_name
                data["version"] = version
        
        constructor: (@service) ->
                window.DoubanFM ?= @
                @player = new Player()
                $(document).ready =>
                        window.T.echo("DoubanFM initialized...")
                        @resume_session()
                
        resume_session: () ->
                #TODO: read cookie to @user

        remember: () ->
                #TODO: write cookie from @user
                
        forget: () ->
                #TODO: clear cookie

        post_login: (data, remember, succ, err) ->
                @user = new User(data)
                if (@user.r == 1)
                        err?(@user)
                        return
                if (remember)
                        @remember
                succ?(@user)
                
        login: (email, password, remember, succ, err) ->
                payload =
                {
                        "email": email,
                        "password": password,
                }
                @attachVersion(payload)
                @service.get(
                        domain + login_url,
                        payload,
                        ((data) =>
                                @post_login(data, remember, succ, err)
                        ),
                        ((status, error) =>
                                data = { r: 1, err: "Internal Error: #{error}" }
                                @post_login(data, remember, succ, err)
                        ))
                return
                
        logout: () ->
                @User = new User()
                @forget()
        #######################################
        # Play Channel
        play: (channel) ->
                @currentChannel = channel
                @player?.play(channel)
        next: () ->
                @player?.nextSong(@player.action.SKIP)
        #######################################
        #
        update: (succ, err) ->
                @doGetChannels(
                        ((json) =>
                                @channels = (new Channel(j) for j in json?.channels)
                                succ(@channels)
                        )
                                ,
                        err
                )
                

        #######################################
        doGetChannels: (succ, err)->
                @service.get(
                        domain + channel_url,
                        {},
                        succ,
                        err)        
                
        doGetSongs: (channel, action, sid, history, succ, err)->
                payload = {
                        "sid": sid,
                        "channel": channel.channel_id ? 0,
                        "type": action ? "n",
                        "h": history ? ""
                }
                @attachVersion(payload)
                @user?.attachAuth(payload)

                @service.get(
                        domain + song_url,
                        payload,
                        succ,
                        err
                )

        #######################################
        doLike: (song) ->
                #TODO:

        doUnlike: (song) ->
                #TODO:
                
        doBoo: (song) ->
                #TODO:

        doSkip: (song) ->
                #TODO:

new DoubanFM(window.Service)
