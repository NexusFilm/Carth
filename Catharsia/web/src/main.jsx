import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { createRoot } from 'react-dom/client'
import { createClient } from '@supabase/supabase-js'
import { QRCodeSVG } from 'qrcode.react'
import {
  ArrowDownRight, ArrowLeft, ArrowRight, ArrowUpRight, BadgeCheck, BookOpenText,
  Bookmark, Brain, Check, ChevronDown, CircleUserRound, Copy, ExternalLink,
  Heart, HeartHandshake, Link2, LogIn, MessageCircle, MoreHorizontal, Plus,
  Search, Settings2, Share2, ShieldCheck, Sparkles, UserRound, Users, X,
} from 'lucide-react'
import './style.css'

const config = {
  url: import.meta.env.VITE_SUPABASE_URL,
  key: import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
  tenant: import.meta.env.VITE_KATHAR_TENANT_ID,
  publicBase: import.meta.env.VITE_PUBLIC_BASE_URL || window.location.origin,
}
const client = config.url && config.key ? createClient(config.url, config.key) : null
const communityFields = 'id,name,topic,description,cover_url,members,member_limit,professional_id,owner_user_id,guidelines,created_at'
const formatDate = value => value ? new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(value)) : ''
const mediaURL = value => {
  if (!value || /^(https?:|blob:|data:)/i.test(value)) return value
  return client?.storage.from('kathar-media').getPublicUrl(value.replace(/^\/+/, '')).data.publicUrl || value
}

function App() {
  const [session, setSession] = useState(null)
  const [authReady, setAuthReady] = useState(false)
  const [canHost, setCanHost] = useState(false)
  const [isAdmin, setIsAdmin] = useState(false)
  const [communities, setCommunities] = useState([])
  const [memberships, setMemberships] = useState([])
  const [posts, setPosts] = useState([])
  const [feed, setFeed] = useState([])
  const [directoryError, setDirectoryError] = useState('')
  const initialCommunity = window.location.pathname.match(/^\/community\/([0-9a-f-]+)$/i)?.[1] || new URLSearchParams(window.location.search).get('community')
  const [selectedCommunityId, setSelectedCommunityId] = useState(initialCommunity)
  const initialPath = window.location.pathname.replace(/\/$/, '')
  const [section, setSection] = useState(initialCommunity ? 'community' : ['saved', 'communities', 'profile'].includes(initialPath.slice(1)) ? initialPath.slice(1) : 'explore')
  const [communityMode, setCommunityMode] = useState('discover')
  const [profilePanel, setProfilePanel] = useState('profile')
  const [savedIDs, setSavedIDs] = useState([])
  const [likedIDs, setLikedIDs] = useState([])
  const [savedRevision, setSavedRevision] = useState(0)
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [authEmail, setAuthEmail] = useState('')
  const [authMessage, setAuthMessage] = useState('')
  const [isAuthOpen, setIsAuthOpen] = useState(false)
  const [isCreateOpen, setIsCreateOpen] = useState(false)
  const [toast, setToast] = useState('')

  const selectedCommunity = useMemo(
    () => communities.find(item => item.id === selectedCommunityId) || null,
    [communities, selectedCommunityId],
  )
  const myGroups = useMemo(() => {
    const joined = new Set(memberships.filter(row => row.status === 'active').map(row => row.community_id))
    return communities.filter(group => joined.has(group.id) || group.owner_user_id === session?.user?.id)
  }, [communities, memberships, session])
  const visibleCommunities = useMemo(() => communities.filter(group =>
    `${group.name} ${group.topic} ${group.description || ''}`.toLowerCase().includes(query.toLowerCase())), [communities, query])

  const notify = useCallback(text => {
    setToast(text)
    window.setTimeout(() => setToast(''), 2600)
  }, [])

  const loadDirectory = useCallback(async () => {
    if (!client || !config.tenant) return
    const { data, error } = await client.from('kathar_communities')
      .select(communityFields).eq('tenant_id', config.tenant)
      .order('members', { ascending: false }).order('created_at', { ascending: false })
      .abortSignal(AbortSignal.timeout(12000))
    if (error) throw error
    setCommunities(data || [])
    setDirectoryError('')
  }, [])

  const loadViewer = useCallback(async activeSession => {
    if (!client || !activeSession?.user) {
      setMemberships([]); setCanHost(false); setIsAdmin(false); setSavedIDs([]); setLikedIDs([]); return
    }
    const userId = activeSession.user.id
    await client.rpc('kathar_ensure_current_user')
    const [{ data: joined }, { data: admin }] = await Promise.all([
      client.from('kathar_community_members').select('id,community_id,status,role')
        .eq('tenant_id', config.tenant).eq('user_id', userId).eq('status', 'active'),
      client.rpc('kathar_is_admin'),
    ])
    const { data: professionals, error: professionalError } = await client.from('kathar_professionals')
      .select('id,credentials').eq('tenant_id', config.tenant).eq('user_id', userId)
      .eq('verified', true).eq('verification_status', 'verified')
      .in('verification_tier', ['verified_clinician', 'verified_professional']).limit(5)
    if (professionalError && !admin) throw professionalError
    const adminValue = admin === true
    const [{ data: saved }, { data: liked }] = await Promise.all([
      client.from('kathar_saved_items').select('target_id').eq('tenant_id', config.tenant).eq('viewer_id', userId).eq('kind', 'post').limit(200),
      client.from('kathar_post_likes').select('post_id').eq('tenant_id', config.tenant).eq('user_id', userId).limit(200),
    ])
    setMemberships(joined || [])
    setIsAdmin(adminValue)
    setCanHost(adminValue || (professionals || []).length > 0)
    setSavedIDs((saved || []).map(row => row.target_id))
    setLikedIDs((liked || []).map(row => row.post_id))
  }, [])

  const loadPageData = useCallback(async () => {
    if (!client || !config.tenant) { setLoading(false); return }
    setLoading(true)
    try {
      try {
        await loadDirectory()
      } catch (error) {
        setDirectoryError(error.message || 'Couldn’t load communities.')
        throw error
      }
      const { data, error } = await client.from('kathar_posts')
        .select('id,title,summary,body,format,topics,link_url,cover_url,media_url,media_items,author_name,author_credentials,created_at,likes,comment_count')
        .eq('tenant_id', config.tenant).eq('is_mock', false).eq('is_test', false)
        .order('created_at', { ascending: false }).limit(25)
        .abortSignal(AbortSignal.timeout(12000))
      if (error) throw error
      setFeed(data || [])
    } catch (error) {
      notify(error.message || 'Couldn’t load the latest content.')
    } finally { setLoading(false) }
  }, [loadDirectory, notify])

  const loadCommunity = useCallback(async group => {
    if (!client || !group || !session) { setPosts([]); return }
    const joined = memberships.some(row => row.community_id === group.id)
    if (!joined && group.owner_user_id !== session.user.id && !isAdmin) { setPosts([]); return }
    const { data, error } = await client.from('kathar_community_posts')
      .select('id,community_id,parent_id,kind,title,format,media_url,link_url,author_user_id,author_name,author_credentials,body,pinned,replies,created_at')
      .eq('tenant_id', config.tenant).eq('community_id', group.id)
      .order('pinned', { ascending: false }).order('created_at', { ascending: false }).limit(100)
    if (error) { notify(error.message); return }
    setPosts(data || [])
  }, [isAdmin, memberships, notify, session])

  useEffect(() => {
    if (!client) { setLoading(false); setAuthReady(true); return }
    let active = true
    client.auth.getSession().then(async ({ data }) => {
      if (!active) return
      setSession(data.session)
      await loadViewer(data.session).catch(error => notify(error.message))
      setAuthReady(true)
    })
    const { data: listener } = client.auth.onAuthStateChange((_event, next) => {
      setSession(next)
      window.setTimeout(() => loadViewer(next).catch(error => notify(error.message)), 0)
    })
    return () => { active = false; listener.subscription.unsubscribe() }
  }, [loadViewer, notify])

  useEffect(() => { loadPageData() }, [loadPageData])
  useEffect(() => {
    if (section === 'community' && selectedCommunity) loadCommunity(selectedCommunity)
    else setPosts([])
  }, [section, selectedCommunity, loadCommunity])

  const openCommunity = group => {
    setSelectedCommunityId(group.id)
    setSection('community')
    const url = new URL(window.location.href)
    url.pathname = `/community/${group.id}`
    url.search = ''
    window.history.pushState({}, '', url)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }
  const goSection = target => {
    const next = target === 'host' ? 'communities' : target
    setSection(next)
    setSelectedCommunityId(null)
    const url = new URL(window.location.href)
    url.pathname = next === 'community' ? '/communities' : `/${next}`
    url.search = ''
    window.history.pushState({}, '', url)
  }
  useEffect(() => {
    const onPop = () => {
      const match = window.location.pathname.match(/^\/community\/([0-9a-f-]+)$/i)
      setSelectedCommunityId(match?.[1] || new URLSearchParams(window.location.search).get('community'))
      const path = window.location.pathname.replace(/\/$/, '').slice(1)
      setSection(match ? 'community' : ['saved', 'communities', 'profile'].includes(path) ? path : 'explore')
    }
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  const signInGoogle = async () => {
    const { error } = await client.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.origin } })
    if (error) setAuthMessage(error.message)
  }
  const signInEmail = async event => {
    event.preventDefault()
    setAuthMessage('Sending a secure sign-in link…')
    const { error } = await client.auth.signInWithOtp({ email: authEmail, options: { emailRedirectTo: window.location.origin } })
    setAuthMessage(error ? error.message : 'Check your email for a secure sign-in link.')
  }
  const signOut = async () => { await client.auth.signOut(); setIsAuthOpen(false); goSection('explore'); notify('Signed out.') }

  const toggleSaved = async post => {
    if (!session) { setIsAuthOpen(true); return }
    const isSaved = savedIDs.includes(post.id)
    const { error } = isSaved
      ? await client.from('kathar_saved_items').delete().eq('tenant_id', config.tenant).eq('viewer_id', session.user.id).eq('kind', 'post').eq('target_id', post.id)
      : await client.from('kathar_saved_items').upsert({ tenant_id: config.tenant, viewer_id: session.user.id, kind: 'post', target_id: post.id },
        { onConflict: 'viewer_id,kind,target_id', ignoreDuplicates: true })
    if (error) { notify(error.message || 'Couldn’t update saved posts.'); return }
    setSavedIDs(current => isSaved ? current.filter(id => id !== post.id) : [...current, post.id])
    setSavedRevision(value => value + 1)
    notify(isSaved ? 'Removed from Saved.' : 'Saved for later.')
  }

  const toggleLiked = async post => {
    if (!session) { setIsAuthOpen(true); return }
    const isLiked = likedIDs.includes(post.id)
    const { data: likes, error } = await client.rpc('kathar_toggle_post_like', { p_post_id: post.id, p_liked: isLiked })
    if (error) { notify(error.message || 'Couldn’t update this appreciation.'); return }
    setLikedIDs(current => isLiked ? current.filter(id => id !== post.id) : [...current, post.id])
    if (typeof likes === 'number') setFeed(current => current.map(item => item.id === post.id ? { ...item, likes } : item))
  }

  const joinCommunity = async group => {
    if (!session) { setIsAuthOpen(true); return }
    try {
      await client.rpc('kathar_ensure_current_user')
      const existing = await client.from('kathar_community_members').select('id,status')
        .eq('tenant_id', config.tenant).eq('community_id', group.id).eq('user_id', session.user.id).limit(1)
      const row = existing.data?.[0]
      if (row?.status === 'active') { notify('You’re already part of this community.'); return }
      if (row) {
        const { error } = await client.from('kathar_community_members').update({ status: 'active', updated_at: new Date().toISOString() }).eq('id', row.id)
        if (error) throw error
      } else {
        const { error } = await client.from('kathar_community_members').insert({
          tenant_id: config.tenant, community_id: group.id, community_owner_id: group.owner_user_id,
          user_id: session.user.id, email: session.user.email, display_name: session.user.user_metadata?.full_name || session.user.email,
          role: 'member', status: 'active',
        })
        if (error) throw error
      }
      await loadViewer(session); await loadDirectory(); notify('You joined the community.');
    } catch (error) { notify(error.message || 'Couldn’t join this community.') }
  }
  const leaveCommunity = async group => {
    if (!session) return
    const { error } = await client.from('kathar_community_members').delete().eq('tenant_id', config.tenant)
      .eq('community_id', group.id).eq('user_id', session.user.id)
    if (error) notify(error.message)
    else { await loadViewer(session); await loadDirectory(); notify('You left the community.') }
  }
  const createCommunity = async form => {
    if (!session || !canHost) throw new Error('Verified therapist access is required to host a community.')
    const { data: professionals, error: professionalError } = await client.from('kathar_professionals')
      .select('id').eq('tenant_id', config.tenant).eq('user_id', session.user.id).eq('verified', true)
      .eq('verification_status', 'verified').in('verification_tier', ['verified_clinician', 'verified_professional']).limit(1)
    if (professionalError && !isAdmin) throw professionalError
    const { error } = await client.from('kathar_communities').insert({
      tenant_id: config.tenant, name: form.name, topic: form.topic, description: form.description,
      guidelines: form.guidelines, member_limit: Number(form.memberLimit), professional_id: professionals?.[0]?.id || null,
      owner_user_id: session.user.id, is_mock: false,
    })
    if (error) throw error
    await loadDirectory(); setIsCreateOpen(false); setCommunityMode('manage'); goSection('communities'); notify('Community created.')
  }
  const saveCommunity = async (group, changes) => {
    const { error } = await client.from('kathar_communities').update({ ...changes, updated_at: new Date().toISOString() })
      .eq('tenant_id', config.tenant).eq('id', group.id)
    if (error) throw error
    await loadDirectory(); notify('Community details updated.')
  }
  const publishCommunityPost = async (group, form) => {
    const hostOwns = group.owner_user_id === session?.user?.id || isAdmin
    const authorName = session?.user?.user_metadata?.full_name || session?.user?.email || 'Community member'
    const { error } = await client.from('kathar_community_posts').insert({
      tenant_id: config.tenant, community_id: group.id, kind: hostOwns ? 'group_post' : 'comment',
      format: hostOwns ? form.format : null, title: hostOwns ? form.title || null : null,
      link_url: hostOwns ? form.link_url || null : null, body: form.body,
      author_user_id: session.user.id, author_name: authorName,
    })
    if (error) throw error
    await loadCommunity(group); notify(hostOwns ? 'Shared with the community.' : 'Comment posted.')
  }
  const removeMember = async member => {
    const { error } = await client.from('kathar_community_members').update({ status: 'removed', updated_at: new Date().toISOString() })
      .eq('tenant_id', config.tenant).eq('id', member.id)
    if (error) notify(error.message)
    else notify('Member removed from the group.')
  }
  const deleteCommunityPost = async post => {
    const { error } = await client.from('kathar_community_posts').delete().eq('tenant_id', config.tenant).eq('id', post.id)
    if (error) notify(error.message)
    else { await loadCommunity(selectedCommunity); notify('Post removed.') }
  }

  if (!client) return <SetupMessage />
  const userOwnsSelected = selectedCommunity?.owner_user_id === session?.user?.id

  return <div className="app-shell">
    <header className="topbar">
      <a className="brand" href="/" onClick={e => { e.preventDefault(); goSection('explore') }}>
        <img className="brand-logo" src="/catharsia-mark.png" alt="" />
        <span><b>Catharsia</b><small>EXPLORE</small></span>
      </a>
      <nav className="topnav" aria-label="Main navigation">
        <SidebarNav section={section} onNavigate={goSection} />
      </nav>
      {session ? <div className="user-menu">
        <button className="user-avatar-button" onClick={() => goSection('profile')} aria-label="Open profile"><UserAvatar session={session} /></button>
        <span className="user-email">{session.user.email}</span>
        <button className="icon-button" aria-label="Sign out" title="Sign out" onClick={signOut}><LogIn size={17} className="flip-icon" /></button>
      </div> : <button className="button button-outline button-small" onClick={() => setIsAuthOpen(true)}>Sign in</button>}
    </header>

    <div className="desktop-workspace">
      <aside className="workspace-sidebar" aria-label="Catharsia navigation and your spaces">
        <SidebarNav section={section} onNavigate={goSection} />
        <div className="sidebar-divider" />
        <div className="sidebar-section-label">YOUR SPACES</div>
        {session && myGroups.length ? <div className="sidebar-groups">{myGroups.slice(0, 5).map(group =>
          <button key={group.id} className="sidebar-group" onClick={() => openCommunity(group)} title={group.name}>
            <span className="sidebar-group-mark"><Users size={14} /></span><span>{group.name}</span>
          </button>)}</div> : <p className="sidebar-empty">{session ? 'Groups you join will appear here.' : 'Sign in to keep your communities close.'}</p>}
        <button className="sidebar-link" onClick={() => goSection('communities')}><Plus size={15} /> Find a community</button>
        {canHost && <button className="sidebar-host-link" onClick={() => { setCommunityMode('manage'); goSection('communities') }}><Settings2 size={15} /> Manage groups <ArrowRight size={14} /></button>}
        <div className="sidebar-bottom">
          <div className="sidebar-divider" />
          {session ? <button className="sidebar-account" onClick={() => goSection('profile')}>
            <UserAvatar session={session} /><span><b>{session.user.user_metadata?.display_name || session.user.user_metadata?.full_name || 'Your profile'}</b><small>{isAdmin ? 'Catharsia admin' : canHost ? 'Verified host' : 'Member account'}</small></span><ArrowRight size={14} />
          </button> : <button className="sidebar-signin" onClick={() => setIsAuthOpen(true)}><LogIn size={15} /> Sign in to interact</button>}
        </div>
      </aside>

      <main className="main-area">
      {section === 'explore' && <ExplorePage feed={feed} loading={loading} session={session} likedIDs={likedIDs} savedIDs={savedIDs}
        onLike={toggleLiked} onSave={toggleSaved} onBrowse={() => goSection('communities')} onSignIn={() => setIsAuthOpen(true)} />}
      {section === 'saved' && <SavedPage session={session} revision={savedRevision} onSignIn={() => setIsAuthOpen(true)} onExplore={() => goSection('explore')} onSave={toggleSaved}
        savedIDs={savedIDs} likedIDs={likedIDs} onLike={toggleLiked} />}
      {section === 'communities' && <CommunitiesHub
        communities={visibleCommunities} myGroups={myGroups} query={query} setQuery={setQuery} loading={loading}
        error={directoryError} onRetry={loadPageData} signedIn={!!session} onOpen={openCommunity} onSignIn={() => setIsAuthOpen(true)}
        canHost={canHost} mode={communityMode} setMode={setCommunityMode} onCreate={() => setIsCreateOpen(true)}
        onSave={saveCommunity} onShare={notify} baseURL={config.publicBase} session={session} isAdmin={isAdmin} />}
      {section === 'community' && selectedCommunity && <CommunityPage
        group={selectedCommunity} posts={posts} session={session} isHost={userOwnsSelected || isAdmin}
        joined={memberships.some(row => row.community_id === selectedCommunity.id)} onBack={() => goSection('communities')}
        onJoin={() => joinCommunity(selectedCommunity)} onLeave={() => leaveCommunity(selectedCommunity)}
        onSignIn={() => setIsAuthOpen(true)} onPublish={form => publishCommunityPost(selectedCommunity, form)}
        onDeletePost={deleteCommunityPost} notify={notify} />}
      {section === 'community' && !selectedCommunity && <CommunitiesHub communities={visibleCommunities} myGroups={myGroups}
        query={query} setQuery={setQuery} loading={loading} error={directoryError} onRetry={loadPageData} signedIn={!!session}
        onOpen={openCommunity} onSignIn={() => setIsAuthOpen(true)} canHost={canHost} mode={communityMode} setMode={setCommunityMode}
        onCreate={() => setIsCreateOpen(true)} onSave={saveCommunity} onShare={notify} baseURL={config.publicBase} session={session} isAdmin={isAdmin} />}
      {section === 'profile' && <ProfilePage session={session} isAdmin={isAdmin} panel={profilePanel} setPanel={setProfilePanel}
        onSignIn={() => setIsAuthOpen(true)} onSignOut={signOut} notify={notify} />}
      </main>
      <ContextSidebar section={section} selectedCommunity={selectedCommunity} session={session} canHost={canHost} isAdmin={isAdmin}
        myGroups={myGroups} onNavigate={goSection} onOpenCommunity={openCommunity} onManage={() => { setCommunityMode('manage'); goSection('communities') }} />
    </div>
    <footer className="footnote"><span>Therapist-led support, built around real conversation.</span><span>Community spaces are not a substitute for individual care.</span></footer>

    {isAuthOpen && <AuthModal email={authEmail} setEmail={setAuthEmail} message={authMessage} setMessage={setAuthMessage}
      onGoogle={signInGoogle} onEmail={signInEmail} onClose={() => setIsAuthOpen(false)} />}
    {isCreateOpen && <CreateModal onClose={() => setIsCreateOpen(false)} onCreate={createCommunity} />}
    {toast && <div className="toast"><Check size={17} />{toast}</div>}
  </div>
}

function SidebarNav({ section, onNavigate }) {
  const items = [
    ['explore', 'Explore', Sparkles], ['saved', 'Saved', Bookmark], ['communities', 'Communities', Users], ['profile', 'Profile', UserRound],
  ]
  return <>{items.map(([key, label, Icon]) => <button key={key} className={`sidebar-nav-item ${section === key || key === 'communities' && section === 'community' ? 'active' : ''}`}
    aria-current={section === key || key === 'communities' && section === 'community' ? 'page' : undefined} onClick={() => onNavigate(key)}>
    <Icon size={17} /><span>{label}</span></button>)}</>
}

function ContextSidebar({ section, selectedCommunity, session, canHost, isAdmin, myGroups, onNavigate, onOpenCommunity, onManage }) {
  if (section === 'community' && selectedCommunity) return <aside className="context-sidebar" aria-label="Community details">
    <div className="context-card context-community"><div className="eyebrow">COMMUNITY</div><h2>{selectedCommunity.name}</h2>
      <p>{selectedCommunity.description || 'A shared space for support, conversation, and helpful resources.'}</p>
      <button className="context-action" onClick={() => onNavigate('communities')}><ArrowLeft size={14} /> All communities</button>
    </div>
    {selectedCommunity.guidelines && <div className="context-card"><div className="context-card-title"><ShieldCheck size={16} /><b>Group guidelines</b></div><p>{selectedCommunity.guidelines}</p></div>}
  </aside>
  return <aside className="context-sidebar" aria-label="Helpful links and account context">
    {section === 'explore' && <>
      <div className="context-card context-feature"><span className="context-icon"><HeartHandshake size={18} /></span><div className="eyebrow">A SPACE TO BE HEARD</div>
        <h2>Support can start with a conversation.</h2><p>Explore therapist-created posts and find a community when you’re ready.</p>
        <button className="context-action" onClick={() => onNavigate('communities')}>Explore communities <ArrowRight size={14} /></button>
      </div>
      <div className="context-card"><div className="context-card-title"><Bookmark size={16} /><b>Keep what helps</b></div><p>Save a post to return to it later.</p><button className="context-text-link" onClick={() => onNavigate('saved')}>Open Saved <ArrowRight size={14} /></button></div>
    </>}
    {section === 'saved' && <div className="context-card context-feature"><span className="context-icon"><Bookmark size={18} /></span><div className="eyebrow">YOUR PRIVATE SHELF</div>
      <h2>Return to something that helped.</h2><p>Your saved posts are private to your account.</p><button className="context-action" onClick={() => onNavigate('explore')}>Back to Explore <ArrowRight size={14} /></button></div>}
    {section === 'communities' && <>
      <div className="context-card context-feature"><span className="context-icon"><Users size={18} /></span><div className="eyebrow">COMMUNITIES</div>
        <h2>Support takes shape together.</h2><p>Join a therapist-led group for ongoing conversation and curated resources.</p>
        {canHost && <button className="context-action" onClick={onManage}>Manage your groups <ArrowRight size={14} /></button>}
      </div>
      <div className="context-card"><div className="context-card-title"><Users size={16} /><b>Your communities</b></div>
        {myGroups.length ? myGroups.slice(0, 4).map(group => <button key={group.id} className="context-group-link" onClick={() => onOpenCommunity(group)}>{group.name}<ArrowRight size={13} /></button>) : <p>{session ? 'Join a community and it will appear here.' : 'Sign in when you’re ready to join a community.'}</p>}
      </div>
    </>}
    {section === 'profile' && <>
      <div className="context-card context-feature"><span className="context-icon"><UserRound size={18} /></span><div className="eyebrow">YOUR ACCOUNT</div>
        <h2>Make your profile yours.</h2><p>Update your photo, display name, username, and bio from this page.</p>
      </div>
      {isAdmin && <div className="context-card context-admin"><div className="context-card-title"><ShieldCheck size={16} /><b>Admin tools</b></div><p>View tenant activity and verification requests.</p><button className="context-action" onClick={() => onNavigate('profile')}>Open Admin in Profile <ArrowRight size={14} /></button></div>}
    </>}
    {section === 'community' && <div className="context-card"><div className="context-card-title"><Users size={16} /><b>Explore groups</b></div><p>Find a community that fits what you need.</p><button className="context-action" onClick={() => onNavigate('communities')}>All communities <ArrowRight size={14} /></button></div>}
  </aside>
}

function SetupMessage() {
  return <main className="setup-screen"><span className="brand-mark"><Brain size={24} /></span><h1>Connect the Catharsia project</h1>
    <p>Add the existing Supabase project URL, publishable key, and tenant ID to <code>.env.local</code> to open Catharsia.</p></main>
}

function PageHeading({ eyebrow, title, description, action }) {
  return <div className="page-heading"><div><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{description}</p></div>{action}</div>
}

function ValueStatement({ icon: Icon, title, text }) {
  return <div className="value-statement"><span className="value-icon"><Icon size={19} /></span><div><b>{title}</b><p>{text}</p></div></div>
}

function UserAvatar({ session }) {
  const label = session?.user?.user_metadata?.display_name || session?.user?.user_metadata?.full_name || session?.user?.email || 'Member'
  const [photo, setPhoto] = useState(session?.user?.user_metadata?.avatar_url || session?.user?.user_metadata?.picture || '')
  useEffect(() => {
    let active = true
    if (!session?.user?.id) { setPhoto(''); return }
    setPhoto(session.user.user_metadata?.avatar_url || session.user.user_metadata?.picture || '')
    client.from('kathar_profiles').select('photo_url').eq('tenant_id', config.tenant).eq('id', session.user.id).maybeSingle()
      .then(({ data }) => { if (active && data?.photo_url) setPhoto(data.photo_url) })
    return () => { active = false }
  }, [session?.user?.id])
  return photo ? <img className="user-avatar" src={photo} alt="" /> : <span className="user-avatar">{label.slice(0, 1).toUpperCase()}</span>
}

function CommunitiesHub({ communities, myGroups, query, setQuery, loading, error, onRetry, signedIn, onOpen, onSignIn,
  canHost, mode, setMode, onCreate, onSave, onShare, baseURL, session, isAdmin }) {
  const managed = isAdmin ? communities : myGroups.filter(group => group.owner_user_id === session?.user?.id)
  return <>
    <PageHeading eyebrow="Find your people, or host a circle" title="Communities" description="Discover therapist-guided spaces and manage your circles in one place."
      action={signedIn ? <span className="counter-chip"><Users size={15} /> {myGroups.length} joined</span> : null} />
    <ValueStatement icon={HeartHandshake} title="Support grows in a shared space" text="Explore open community details or, as a verified therapist, host conversation and resources for your group." />
    {canHost && <div className="section-switch" role="tablist" aria-label="Community workspace">
      <button role="tab" aria-selected={mode === 'discover'} className={mode === 'discover' ? 'selected' : ''} onClick={() => setMode('discover')}><Search size={15} /> Discover</button>
      <button role="tab" aria-selected={mode === 'manage'} className={mode === 'manage' ? 'selected' : ''} onClick={() => setMode('manage')}><Settings2 size={15} /> Manage groups <span>{managed.length}</span></button>
    </div>}
    {mode === 'manage' && canHost ? <HostStudio communities={managed} canHost={canHost} session={session} onCreate={onCreate} onOpen={onOpen}
      onSave={onSave} onShare={onShare} baseURL={baseURL} /> : <CommunityDirectory communities={communities} myGroups={myGroups} query={query}
      setQuery={setQuery} loading={loading} error={error} onRetry={onRetry} signedIn={signedIn} onOpen={onOpen} onSignIn={onSignIn} showHeading={false} />}
  </>
}

function PostCard({ post, session, liked, saved, onLike, onSave, onSignIn }) {
  return <article className="feed-card">
    <PostMedia post={post} />
    <div className="feed-content">
      <div className="feed-author"><span className="small-avatar"><Brain size={15} /></span><div><b>{post.author_name || 'Catharsia therapist'}</b>
        <small>{post.author_credentials || 'Verified therapist'} · {formatDate(post.created_at)}</small></div><BadgeCheck className="verified-mark" size={17} /></div>
      <h2>{post.title || post.summary || post.body || 'A note for today'}</h2>{post.body && post.body !== post.title && post.body !== post.summary && <p>{post.body}</p>}
      <div className="post-meta"><span><MessageCircle size={15} /> {post.comment_count || post.comments_count || 0} conversations</span><span>{post.likes || 0} appreciations</span></div>
      <div className="post-actions">
        <button className={liked ? 'selected' : ''} onClick={session ? onLike : onSignIn} aria-pressed={liked}><Heart size={17} fill={liked ? 'currentColor' : 'none'} /> Appreciate</button>
        <button className={saved ? 'selected' : ''} onClick={session ? onSave : onSignIn} aria-pressed={saved}><Bookmark size={17} fill={saved ? 'currentColor' : 'none'} /> {saved ? 'Saved' : 'Save'}</button>
      </div>
    </div>
  </article>
}

function SavedPage({ session, revision, savedIDs, likedIDs, onSave, onLike, onSignIn, onExplore }) {
  const [posts, setPosts] = useState([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [reloadKey, setReloadKey] = useState(0)
  useEffect(() => {
    let active = true
    if (!session) { setPosts([]); setLoading(false); setError(''); return }
    const load = async () => {
      setLoading(true); setError('')
      try {
        const { data: rows, error: savedError } = await client.from('kathar_saved_items').select('target_id,created_at')
          .eq('tenant_id', config.tenant).eq('viewer_id', session.user.id).eq('kind', 'post').order('created_at', { ascending: false }).limit(100)
        if (savedError) throw savedError
        const ids = (rows || []).map(row => row.target_id)
        if (!ids.length) { if (active) setPosts([]); return }
        const { data, error: postError } = await client.from('kathar_posts')
          .select('id,title,summary,body,format,topics,link_url,cover_url,media_url,media_items,author_name,author_credentials,created_at,likes,comment_count,comments_count')
          .eq('tenant_id', config.tenant).eq('is_mock', false).eq('is_test', false).in('id', ids)
        if (postError) throw postError
        const order = new Map(ids.map((id, index) => [id, index]))
        if (active) setPosts((data || []).sort((a, b) => order.get(a.id) - order.get(b.id)))
      } catch (cause) { if (active) setError(cause.message || 'Saved posts could not load.') }
      finally { if (active) setLoading(false) }
    }
    load()
    return () => { active = false }
  }, [session, revision, reloadKey])
  return <>
    <PageHeading eyebrow="Keep what helps" title="Saved" description="A quiet shelf for thoughts and resources you want to return to." />
    {!session ? <SignInPanel onSignIn={onSignIn} title="Your saved posts live here" text="Sign in to keep a private collection of posts you want to revisit." /> :
      loading ? <div className="loading-state" role="status">Gathering your saved posts…</div> : error ? <div className="error-panel" role="alert"><div><h2>Saved posts couldn’t load</h2><p>{error}</p></div><button className="button button-outline button-small" onClick={() => setReloadKey(value => value + 1)}>Try again</button></div> : posts.length ?
        <div className="feed-grid saved-grid">{posts.map(post => <PostCard key={post.id} post={post} session={session} liked={likedIDs.includes(post.id)} saved={savedIDs.includes(post.id)}
          onLike={() => onLike(post)} onSave={() => onSave(post)} onSignIn={onSignIn} />)}</div> :
        <div className="empty-panel saved-empty"><span className="saved-empty-mark"><Bookmark size={25} /></span><h2>Make a little space for what matters</h2><p>Save a post from Explore and it will be easy to find here later.</p><button className="button button-outline" onClick={onExplore}>Go to Explore <ArrowRight size={15} /></button></div>}
  </>
}

function SignInPanel({ onSignIn, title, text }) {
  return <div className="join-panel account-gate"><div className="join-mark"><UserRound size={20} /></div><h2>{title}</h2><p>{text}</p><button className="button button-primary" onClick={onSignIn}>Sign in <ArrowRight size={16} /></button><small>Explore remains open without an account.</small></div>
}

function ProfilePage({ session, isAdmin, panel, setPanel, onSignIn, onSignOut, notify }) {
  return <>
    <PageHeading eyebrow="Your Catharsia account" title="Profile" description="Manage the details people see and your account access." />
    {!session ? <SignInPanel onSignIn={onSignIn} title="Your profile starts here" text="Sign in to set your name, username, and profile photo." /> : <>
      <div className="profile-tabs" role="tablist" aria-label="Profile sections">
        <button role="tab" aria-selected={panel === 'profile'} className={panel === 'profile' ? 'selected' : ''} onClick={() => setPanel('profile')}><UserRound size={15} /> My profile</button>
        {isAdmin && <button role="tab" aria-selected={panel === 'admin'} className={panel === 'admin' ? 'selected' : ''} onClick={() => setPanel('admin')}><ShieldCheck size={15} /> Admin</button>}
      </div>
      {panel === 'admin' && isAdmin ? <AdminDashboard notify={notify} /> : <MemberProfileEditor session={session} onSignOut={onSignOut} notify={notify} />}
    </>}
  </>
}

function MemberProfileEditor({ session, onSignOut, notify }) {
  const [profile, setProfile] = useState({ full_name: '', username: '', bio: '', photo_url: '' })
  const [file, setFile] = useState(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const preview = useMemo(() => file ? URL.createObjectURL(file) : profile.photo_url, [file, profile.photo_url])
  useEffect(() => () => { if (file && preview?.startsWith('blob:')) URL.revokeObjectURL(preview) }, [file, preview])
  useEffect(() => {
    let active = true
    const load = async () => {
      setLoading(true); setError('')
      try {
        const { error: ensureError } = await client.rpc('kathar_ensure_current_user')
        if (ensureError) throw ensureError
        const { data, error: profileError } = await client.from('kathar_profiles').select('full_name,display_name,username,photo_url,bio')
          .eq('tenant_id', config.tenant).eq('id', session.user.id).maybeSingle()
        if (profileError) throw profileError
        if (active) setProfile({ full_name: data?.full_name || data?.display_name || session.user.user_metadata?.full_name || '',
          username: data?.username || '', bio: data?.bio || '', photo_url: data?.photo_url || '' })
      } catch (cause) { if (active) setError(cause.message || 'Your profile could not load.') }
      finally { if (active) setLoading(false) }
    }
    load()
    return () => { active = false }
  }, [session])
  const save = async event => {
    event.preventDefault(); setSaving(true); setError('')
    const name = profile.full_name.trim()
    const username = profile.username.trim().replace(/^@/, '').toLowerCase()
    if (!name || name.length > 60) { setError('Use a display name between 1 and 60 characters.'); setSaving(false); return }
    if (username && !/^[a-z0-9_]{3,24}$/.test(username)) { setError('Usernames use 3–24 lowercase letters, numbers, or underscores.'); setSaving(false); return }
    if (file && (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 4 * 1024 * 1024)) {
      setError('Choose a JPEG, PNG, or WebP image under 4 MB.'); setSaving(false); return
    }
    let uploadedPath = ''
    try {
      let photoURL = profile.photo_url || null
      if (file) {
        const extension = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg'
        uploadedPath = `${config.tenant}/${session.user.id}/${crypto.randomUUID()}.${extension}`
        const { error: uploadError } = await client.storage.from('kathar-profile-avatars').upload(uploadedPath, file, { contentType: file.type, cacheControl: '31536000', upsert: false })
        if (uploadError) throw uploadError
        photoURL = client.storage.from('kathar-profile-avatars').getPublicUrl(uploadedPath).data.publicUrl
      }
      const { data, error: updateError } = await client.from('kathar_profiles').update({
        full_name: name, display_name: name, username: username || null, bio: profile.bio.trim().slice(0, 260), photo_url: photoURL, updated_at: new Date().toISOString(),
      }).eq('tenant_id', config.tenant).eq('id', session.user.id).select('id').maybeSingle()
      if (updateError) throw updateError
      if (!data) throw new Error('Your profile was not saved. Please reload and try again.')
      if (profile.photo_url && file) {
        const old = profile.photo_url.split('/storage/v1/object/public/kathar-profile-avatars/')[1]
        if (old) await client.storage.from('kathar-profile-avatars').remove([decodeURIComponent(old)]).catch(() => {})
      }
      setProfile(current => ({ ...current, full_name: name, username, photo_url: photoURL }))
      setFile(null); notify('Profile saved.')
    } catch (cause) {
      if (uploadedPath) await client.storage.from('kathar-profile-avatars').remove([uploadedPath]).catch(() => {})
      setError(cause.message || 'Your profile could not be saved.')
    } finally { setSaving(false) }
  }
  const removePhoto = () => { setFile(null); setProfile(current => ({ ...current, photo_url: '' })) }
  if (loading) return <div className="loading-state" role="status">Loading your profile…</div>
  return <div className="profile-layout">
    <section className="profile-preview panel-card">
      <div className="profile-avatar-large">{preview ? <img src={preview} alt="Profile" /> : <span>{profile.full_name.slice(0, 1).toUpperCase() || 'C'}</span>}</div>
      <div className="eyebrow">Public profile</div><h2>{profile.full_name || 'Your name'}</h2><p>{profile.username ? `@${profile.username}` : 'Choose a username'}</p>
      {profile.bio && <div className="profile-bio">{profile.bio}</div>}
      <div className="profile-email"><ShieldCheck size={15} /> {session.user.email} <span>Private</span></div>
    </section>
    <form className="profile-form panel-card" onSubmit={save}>
      <div className="card-head"><div><div className="eyebrow">Account settings</div><h2>Edit your profile</h2></div><UserRound size={19} /></div>
      <label>Profile photo<input className="file-input" type="file" accept="image/jpeg,image/png,image/webp" onChange={event => setFile(event.target.files?.[0] || null)} /></label>
      {preview && <button type="button" className="text-button remove-photo" onClick={removePhoto}>Remove photo</button>}
      <label>Display name<input className="clean-input" value={profile.full_name} maxLength="60" onChange={event => setProfile({ ...profile, full_name: event.target.value })} placeholder="Name people see" /></label>
      <label>Username<div className="username-input"><span>@</span><input className="clean-input" value={profile.username} maxLength="24" onChange={event => setProfile({ ...profile, username: event.target.value })} placeholder="username" /></div></label>
      <label>Bio <small>Optional · 260 characters</small><textarea className="clean-input" rows="4" maxLength="260" value={profile.bio} onChange={event => setProfile({ ...profile, bio: event.target.value })} placeholder="A few words about what matters to you" /></label>
      {error && <p className="form-error profile-error" role="alert">{error}</p>}
      <div className="profile-form-footer"><span>Your email stays private.</span><button className="button button-primary" disabled={saving}>{saving ? 'Saving…' : 'Save profile'} <Check size={15} /></button></div>
      <button type="button" className="button button-outline signout-button" onClick={onSignOut}><LogIn size={16} className="flip-icon" /> Sign out</button>
    </form>
  </div>
}

function AdminDashboard() {
  const [counts, setCounts] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [updatedAt, setUpdatedAt] = useState('')
  const refresh = useCallback(async () => {
    setLoading(true); setError('')
    const base = () => client
    const requests = [
      base().from('kathar_profiles').select('id', { count: 'exact', head: true }).eq('tenant_id', config.tenant).or('deactivated.is.null,deactivated.eq.false'),
      base().from('kathar_posts').select('id', { count: 'exact', head: true }).eq('tenant_id', config.tenant).eq('is_mock', false).eq('is_test', false),
      base().from('kathar_communities').select('id', { count: 'exact', head: true }).eq('tenant_id', config.tenant).eq('is_mock', false),
      base().from('kathar_community_members').select('id', { count: 'exact', head: true }).eq('tenant_id', config.tenant).eq('status', 'active'),
      base().from('kathar_verification_applications').select('id', { count: 'exact', head: true }).eq('tenant_id', config.tenant).in('status', ['submitted', 'in_review']),
    ]
    try {
      const results = await Promise.all(requests)
      const failed = results.find(result => result.error)
      if (failed) throw failed.error
      setCounts({ members: results[0].count || 0, posts: results[1].count || 0, communities: results[2].count || 0, memberships: results[3].count || 0, applications: results[4].count || 0 })
      setUpdatedAt(new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }))
    } catch (cause) { setError(cause.message || 'Admin metrics could not load.') }
    finally { setLoading(false) }
  }, [])
  useEffect(() => { refresh() }, [refresh])
  return <section className="admin-dashboard">
    <div className="admin-heading"><div><div className="eyebrow">Catharsia operations</div><h2>Admin overview</h2><p>Live counts from the Catharsia tenant.</p></div><button className="button button-outline button-small" onClick={refresh} disabled={loading}>{loading ? 'Updating…' : 'Refresh'}</button></div>
    {error ? <div className="error-panel" role="alert"><div><h2>Metrics couldn’t load</h2><p>{error}</p></div><button className="button button-outline button-small" onClick={refresh}>Try again</button></div> :
      <div className="admin-metrics" aria-live="polite">{[
        ['People', counts?.members, 'active Catharsia accounts', Users],
        ['Posts', counts?.posts, 'published posts', MessageCircle],
        ['Communities', counts?.communities, 'therapist-led spaces', HeartHandshake],
        ['Memberships', counts?.memberships, 'active group memberships', UserRound],
        ['Applications', counts?.applications, 'open verification reviews', ShieldCheck],
      ].map(([label, value, detail, Icon]) => <article className="metric-card" key={label}><span className="metric-icon"><Icon size={18} /></span><div className="metric-value">{loading ? '—' : value}</div><b>{label}</b><small>{detail}</small></article>)}</div>}
    {updatedAt && <p className="metrics-updated">Updated {updatedAt} · counts respect the tenant’s access rules</p>}
    <div className="admin-access-note"><ShieldCheck size={16} /><span>Admin tools are visible only when Supabase confirms administrator access.</span></div>
  </section>
}

function ExplorePage({ feed, loading, session, likedIDs, savedIDs, onLike, onSave, onBrowse, onSignIn }) {
  return <>
    <PageHeading eyebrow="A steadier kind of social space" title="Explore" description="Short perspectives and practical ideas from trusted therapists." />
    <ValueStatement icon={HeartHandshake} title="Useful voices, in a calmer feed" text="Explore therapist-led ideas at your own pace, then keep learning together in a community." />
    {loading ? <div className="loading-state">Gathering the latest posts…</div> : feed.length === 0 ? <div className="empty-panel"><Brain size={30} /><h2>Your next useful thought is coming</h2><p>New therapist perspectives will appear here as they’re shared.</p><button className="button button-outline" onClick={onBrowse}>Explore communities <ArrowRight size={16} /></button></div> :
      <div className="feed-grid">{feed.map(post => <PostCard key={post.id} post={post} session={session} liked={likedIDs.includes(post.id)} saved={savedIDs.includes(post.id)}
        onLike={() => onLike(post)} onSave={() => onSave(post)} onSignIn={onSignIn} />)}</div>}
    <button className="soft-next" onClick={onBrowse}>Find a community <ArrowRight size={16} /></button>
  </>
}

function PostMedia({ post }) {
  const entries = (Array.isArray(post.media_items) ? post.media_items : [])
    .filter(item => item && (item.path || item.url))
  const items = entries.length ? entries : [post.cover_url || post.media_url].filter(Boolean).map(path => ({ path }))
  if (!items.length) return null
  return <div className="post-media" aria-label={items.length > 1 ? `Post media, ${items.length} items` : 'Post media'}>
    {items.map((item, index) => {
      const src = mediaURL(item.url || item.path)
      const isVideo = item.kind === 'video' || item.mime_type?.startsWith('video/') || item.type === 'video'
      return <div className="post-media-slide" key={`${src}-${index}`}>
        {isVideo ? <video src={src} controls playsInline preload="metadata" aria-label={`Post video ${index + 1}`} /> :
          <img src={src} alt={items.length > 1 ? `Post image ${index + 1} of ${items.length}` : 'Post image'} loading="lazy" />}
      </div>
    })}
    {items.length > 1 && <span className="post-media-count">1 / {items.length}</span>}
  </div>
}

function CommunityDirectory({ communities, myGroups, query, setQuery, loading, error, onRetry, signedIn, onOpen, onSignIn, showHeading = true }) {
  return <>
    {showHeading && <>
      <PageHeading eyebrow="Support, with people who get it" title="Communities" description="Therapist-guided spaces built around shared needs, conversation, and helpful resources." action={signedIn ? <span className="counter-chip"><Users size={15} /> {myGroups.length} joined</span> : null} />
      <ValueStatement icon={Users} title="A place to feel less alone" text="Join a small, guided circle to learn together, share at your pace, and find resources curated for the group." />
    </>}
    <div className="directory-tools"><div className="search-box"><Search size={17} /><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Search by topic or name" /></div>
      {!signedIn && <button className="text-button" onClick={onSignIn}>Sign in to join <ArrowUpRight size={15} /></button>}</div>
    {loading ? <div className="loading-state" role="status" aria-live="polite">Finding communities…</div> : error ?
      <div className="error-panel" role="alert"><div><h2>Communities couldn’t load</h2><p>{error}</p></div><button className="button button-outline button-small" onClick={onRetry}>Try again</button></div> : communities.length === 0 ? <div className="empty-panel"><Users size={30} /><h2>No communities yet</h2><p>There aren’t any communities available right now. Please check back soon.</p></div> :
      <div className="community-grid">{communities.map((group, index) => <CommunityTile key={group.id} group={group} index={index} onClick={() => onOpen(group)} />)}</div>}
  </>
}

function CommunityTile({ group, index, onClick }) {
  const color = ['lavender', 'mint', 'rose', 'blue'][index % 4]
  return <button className={`community-tile ${color}`} onClick={onClick}>
    <div className="tile-top"><span className="tile-mark"><Users size={20} /></span><span className="tile-members">{group.members} members</span></div>
    <div><div className="tile-topic">{group.topic}</div><h2>{group.name}</h2><p>{group.description || 'A space to share support and practical resources.'}</p></div>
    <div className="tile-bottom"><span><BadgeCheck size={15} /> Therapist-led</span><ArrowUpRight size={18} /></div>
  </button>
}

function CommunityPage({ group, posts, session, isHost, joined, onBack, onJoin, onLeave, onSignIn, onPublish, onDeletePost, notify }) {
  const [showRoster, setShowRoster] = useState(false)
  const [roster, setRoster] = useState([])
  const [postDraft, setPostDraft] = useState({ format: 'guidance', title: '', body: '', link_url: '' })
  const [posting, setPosting] = useState(false)
  const isFull = group.members >= group.member_limit

  useEffect(() => {
    if (!isHost || !client || !session) return
    client.from('kathar_community_members').select('id,user_id,display_name,role,status,created_at')
      .eq('tenant_id', config.tenant).eq('community_id', group.id).eq('status', 'active')
      .order('created_at', { ascending: true }).then(({ data, error }) => {
        if (error) notify(error.message); else setRoster(data || [])
      })
  }, [group.id, isHost, notify, session])

  const submit = async event => {
    event.preventDefault()
    if (!postDraft.body.trim()) return
    if (isHost && postDraft.format === 'resource' && (!postDraft.title.trim() || !/^https:\/\//i.test(postDraft.link_url))) {
      notify('Add a title and a valid secure https link.'); return
    }
    setPosting(true)
    try { await onPublish({ ...postDraft, format: postDraft.format === 'resource' ? 'resource' : 'guidance' }); setPostDraft({ format: 'guidance', title: '', body: '', link_url: '' }) }
    catch (error) { notify(error.message || 'Couldn’t post to this group.') }
    finally { setPosting(false) }
  }

  return <>
    <button className="back-link" onClick={onBack}><ArrowLeft size={16} /> All communities</button>
    <div className="community-detail-grid">
      <section className="community-main-col">
        <div className="community-cover">
          {group.cover_url ? <img src={mediaURL(group.cover_url)} alt="" /> : <div className="cover-art"><div className="cover-orb"/><Users size={38} /></div>}
          <div className="cover-caption"><span>{group.topic}</span><h1>{group.name}</h1></div>
        </div>
        <div className="detail-value"><div className="eyebrow">What this space is for</div><p>{group.description || 'A therapist-guided place to connect around a shared experience and find practical resources.'}</p></div>
        <div className="discussion-heading"><div><div className="eyebrow">The conversation</div><h2>{joined || isHost ? 'Inside the group' : 'A group that grows together'}</h2></div>
          {isHost && <span className="counter-chip"><MessageCircle size={15} /> {posts.length} posts</span>}</div>
        {joined || isHost ? <>
          <form className="composer-card" onSubmit={submit}>
            {isHost && <div className="composer-tabs"><button type="button" className={postDraft.format === 'guidance' ? 'selected' : ''} onClick={() => setPostDraft({ ...postDraft, format: 'guidance' })}><Sparkles size={14} /> Guidance</button><button type="button" className={postDraft.format === 'resource' ? 'selected' : ''} onClick={() => setPostDraft({ ...postDraft, format: 'resource' })}><Link2 size={14} /> Resource</button></div>}
            {isHost && postDraft.format === 'resource' && <><input className="clean-input" placeholder="Resource title" value={postDraft.title} onChange={e => setPostDraft({ ...postDraft, title: e.target.value })}/><input className="clean-input" placeholder="Secure link (https://)" value={postDraft.link_url} onChange={e => setPostDraft({ ...postDraft, link_url: e.target.value })}/></>}
            <textarea placeholder={isHost ? 'Share a thoughtful note with your group…' : 'Add a thought to the conversation…'} value={postDraft.body} onChange={e => setPostDraft({ ...postDraft, body: e.target.value })} rows="3" />
            <div className="composer-footer"><span>{isHost ? 'Your community, your guidance' : 'Be kind. Share at your own pace.'}</span><button className="button button-primary button-small" disabled={!postDraft.body.trim() || posting}>{posting ? 'Posting…' : 'Share'} <ArrowUpRight size={15} /></button></div>
          </form>
          {posts.length ? <div className="discussion-list">{posts.map(post => <article className="discussion-card" key={post.id}>
            <div className="discussion-card-head"><span className="small-avatar"><CircleUserRound size={17}/></span><div><b>{post.kind === 'group_post' ? (post.author_name || 'Therapist host') : (post.author_name || 'Community member')}</b><small>{post.kind === 'group_post' ? 'THERAPIST' : 'COMMUNITY'} · {formatDate(post.created_at)}</small></div>
              {isHost && <button className="icon-button small" title="Remove post" aria-label="Remove post" onClick={() => onDeletePost(post)}><MoreHorizontal size={18}/></button>}</div>
            {post.title && <h3>{post.title}</h3>}<p>{post.body}</p>{post.link_url && <a className="resource-link" href={post.link_url} target="_blank" rel="noreferrer"><BookOpenText size={16}/> Open this resource <ExternalLink size={13}/></a>}
          </article>)}</div> : <div className="empty-panel compact"><MessageCircle size={26}/><h2>Begin the conversation</h2><p>Share a welcome thought or ask a question.</p></div>}
        </> : <div className="join-panel"><div className="join-mark"><HeartHandshake size={20}/></div><h2>Find support in a shared space</h2><p>Join to take part in therapist-guided conversation and access the resources shared with this group.</p>
          <button className="button button-primary" disabled={isFull} onClick={session ? onJoin : onSignIn}>{isFull ? 'Community is full' : session ? 'Join this community' : 'Sign in to join'} <ArrowRight size={16}/></button>
          {!session && <small>Browsing stays open. Sign in only when you join or post.</small>}
        </div>}
      </section>
      <aside className="community-side-col">
        <div className="side-card group-facts"><div className="eyebrow">A guided circle</div><div className="fact-row"><span>Community size</span><b>{group.members} / {group.member_limit}</b></div><div className="capacity-track"><span style={{ width: `${Math.min(100, Math.round(group.members / Math.max(1, group.member_limit) * 100))}%` }}/></div><div className="fact-row"><span>Format</span><b>Therapist-led</b></div><div className="fact-row"><span>Opened</span><b>{formatDate(group.created_at)}</b></div>
          {joined && !isHost && <button className="text-button leave-button" onClick={onLeave}>Leave group</button>}
        </div>
        {group.guidelines && <div className="side-card guidelines"><div className="side-title"><ShieldCheck size={17}/><b>Shared expectations</b></div><p>{group.guidelines}</p></div>}
        {isHost && <div className="side-card roster-card"><button className="side-title roster-toggle" onClick={() => setShowRoster(!showRoster)}><Users size={17}/><b>Your people</b><span>{roster.length}</span><ChevronDown size={16} className={showRoster ? 'turned' : ''}/></button>
          {showRoster && <div className="roster-list">{roster.length ? roster.map(member => <div className="roster-row" key={member.id}><span className="tiny-avatar">{(member.display_name || 'M').slice(0, 1).toUpperCase()}</span><span>{member.display_name || 'Member'}</span>{member.user_id !== session?.user?.id && <button onClick={async () => { const { error } = await client.from('kathar_community_members').update({ status: 'removed', updated_at: new Date().toISOString() }).eq('tenant_id', config.tenant).eq('id', member.id); if (error) notify(error.message); else { setRoster(current => current.filter(person => person.id !== member.id)); notify('Member removed.') } }} aria-label="Remove member"><X size={13}/></button>}</div>) : <p>No members yet. Share your group link to invite people.</p>}</div>}
        </div>}
      </aside>
    </div>
  </>
}

function HostStudio({ communities, canHost, session, onCreate, onOpen, onSave, onShare, baseURL }) {
  const [selectedId, setSelectedId] = useState(communities[0]?.id || '')
  const [edit, setEdit] = useState(null)
  const [saving, setSaving] = useState(false)
  useEffect(() => { if (!communities.some(group => group.id === selectedId)) setSelectedId(communities[0]?.id || '') }, [communities, selectedId])
  const group = communities.find(item => item.id === selectedId)
  useEffect(() => { setEdit(group ? { name: group.name, topic: group.topic, description: group.description || '', guidelines: group.guidelines || '', member_limit: group.member_limit } : null) }, [group?.id])
  if (!canHost) return <div className="access-card"><ShieldCheck size={28}/><h2>Host access is for verified therapists</h2><p>Explore stays open while professional access is confirmed.</p></div>
  const shareURL = group ? `${baseURL.replace(/\/$/, '')}/community/${group.id}` : ''
  const save = async event => { event.preventDefault(); setSaving(true); try { await onSave(group, { ...edit, member_limit: Number(edit.member_limit) }) } catch (error) { onShare(error.message || 'Couldn’t update the community.') } finally { setSaving(false) } }
  const copyLink = async () => { try { await navigator.clipboard.writeText(shareURL); onShare('Community link copied.') } catch { onShare(shareURL) } }
  const downloadCard = () => {
    const svg = document.querySelector('#community-qr svg')
    if (!svg) return
    const copy = svg.cloneNode(true)
    copy.setAttribute('xmlns', 'http://www.w3.org/2000/svg')
    copy.setAttribute('width', '220'); copy.setAttribute('height', '220')
    const title = xmlEscape(group.name)
    const focus = xmlEscape(group.topic)
    const description = xmlEscape(group.description || 'A therapist-guided place for support, conversation, and helpful resources.')
    const qr = new XMLSerializer().serializeToString(copy)
    const card = `<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1350" viewBox="0 0 1080 1350">
      <defs><linearGradient id="wash" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#f2ebfb"/><stop offset="1" stop-color="#e6f5f0"/></linearGradient><linearGradient id="ink" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#6943b5"/><stop offset="1" stop-color="#087e73"/></linearGradient></defs>
      <rect width="1080" height="1350" rx="56" fill="url(#wash)"/><rect x="52" y="52" width="976" height="1246" rx="46" fill="#fff" opacity=".87"/>
      <circle cx="160" cy="150" r="42" fill="url(#ink)"/><path d="M150 126c-17 1-23 15-19 27-13 8-11 25 2 31 1 15 20 20 29 10 9 10 28 5 29-10 13-6 15-23 2-31 4-12-2-26-19-27-10-5-19-5-24 0Z" fill="#fff" opacity=".95"/>
      <text x="226" y="143" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="28" font-weight="800" letter-spacing="5" fill="#29223a">CATHARSIA</text><text x="228" y="176" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="17" font-weight="700" letter-spacing="3" fill="#087e73">THERAPIST-LED COMMUNITY</text>
      <text x="110" y="335" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="19" font-weight="800" letter-spacing="4" fill="#087e73">A SHARED SPACE FOR SUPPORT</text>
      <text x="110" y="430" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="64" font-weight="800" letter-spacing="-2" fill="#29223a">${title}</text>
      <text x="112" y="486" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="24" font-weight="700" fill="#6943b5">${focus}</text>
      <text x="112" y="560" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="25" fill="#706a7f"><tspan x="112" dy="0">${description.slice(0, 72)}</tspan><tspan x="112" dy="38">${description.slice(72, 144)}</tspan></text>
      <rect x="110" y="680" width="860" height="440" rx="32" fill="#f8f5fc"/><text x="158" y="745" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="18" font-weight="800" letter-spacing="2" fill="#29223a">SCAN TO EXPLORE THIS COMMUNITY</text>
      <rect x="154" y="786" width="244" height="244" rx="19" fill="#fff"/>${qr.replace('<svg ', '<svg x="166" y="797" ')}
      <text x="450" y="840" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="29" font-weight="800" fill="#29223a">Explore at your pace.</text>
      <text x="450" y="894" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="21" fill="#706a7f"><tspan x="450">Join when you’re ready to</tspan><tspan x="450" dy="34">take part in the conversation.</tspan></text>
      <rect x="450" y="1000" width="345" height="61" rx="30" fill="#7048bc"/><text x="622" y="1039" text-anchor="middle" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="18" font-weight="800" fill="#fff">JOIN THE COMMUNITY</text>
      <text x="110" y="1202" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="17" fill="#706a7f">Therapist-guided community · Catharsia</text>
      <text x="110" y="1243" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="14" fill="#8b8494">Community support is educational and does not replace individual care.</text>
    </svg>`
    const blob = new Blob([card], { type: 'image/svg+xml' })
    const url = URL.createObjectURL(blob); const link = document.createElement('a')
    link.href = url; link.download = `catharsia-community-${group.id}-share-card.svg`; link.click(); URL.revokeObjectURL(url)
  }
  return <>
    <PageHeading eyebrow="Your therapist workspace" title="Host studio" description="Build a circle, guide the conversation, and share the space with your community." action={<button className="button button-primary" onClick={onCreate}><Plus size={16}/> New community</button>} />
    <ValueStatement icon={HeartHandshake} title="Support that grows beyond a session" text="Bring people together, share resources, and keep helpful conversations organized in one therapist-guided space." />
    {!communities.length ? <div className="empty-panel"><Users size={30}/><h2>Open your first community</h2><p>Create a guided group with a clear purpose, shared expectations, and a link you can send to your audience.</p><button className="button button-primary" onClick={onCreate}><Plus size={16}/> Create community</button></div> : <div className="host-layout">
      <aside className="host-list"><div className="host-list-head"><span>YOUR GROUPS</span><b>{communities.length}</b></div>{communities.map(item => <button className={item.id === selectedId ? 'host-list-item selected' : 'host-list-item'} key={item.id} onClick={() => setSelectedId(item.id)}><span className="host-list-icon"><Users size={16}/></span><span><b>{item.name}</b><small>{item.members} members · {item.topic}</small></span><ArrowRight size={15}/></button>)}</aside>
      {group && edit && <div className="host-main">
        <div className="host-metrics"><div><span>{group.members}</span><small>MEMBERS</small></div><div><span>{group.member_limit - group.members}</span><small>OPEN SPOTS</small></div><div><span>{group.topic}</span><small>GROUP FOCUS</small></div></div>
        <div className="host-columns">
          <form className="side-card edit-group" onSubmit={save}><div className="card-head"><div><div className="eyebrow">Your group</div><h2>Details</h2></div><Settings2 size={18}/></div>
            <label>Community name<input className="clean-input" value={edit.name} onChange={e => setEdit({ ...edit, name: e.target.value })} required/></label>
            <label>Focus<input className="clean-input" value={edit.topic} onChange={e => setEdit({ ...edit, topic: e.target.value })} required/></label>
            <label>Description<textarea className="clean-input" rows="3" value={edit.description} onChange={e => setEdit({ ...edit, description: e.target.value })}/></label>
            <label>Shared expectations<textarea className="clean-input" rows="3" value={edit.guidelines} onChange={e => setEdit({ ...edit, guidelines: e.target.value })}/></label>
            <label>Member limit<input className="clean-input" type="number" min="2" max="500" value={edit.member_limit} onChange={e => setEdit({ ...edit, member_limit: e.target.value })}/></label>
            <button className="button button-primary" disabled={saving}>{saving ? 'Saving…' : 'Save details'} <Check size={16}/></button>
          </form>
          <div className="share-stack">
            <div className="side-card share-card"><div className="card-head"><div><div className="eyebrow">Share the invitation</div><h2>Bring your people in</h2></div><Share2 size={18}/></div>
              <div className="share-preview"><span className="share-preview-mark"><Brain size={22}/></span><div><small>CATHARSIA COMMUNITY</small><b>{group.name}</b><span>{group.topic} · Therapist-led</span></div><ArrowUpRight size={19}/></div>
              <div className="share-link-row"><Link2 size={15}/><span>{shareURL.replace(/^https?:\/\//, '')}</span><button onClick={copyLink} title="Copy link"><Copy size={15}/></button></div>
              <div className="qr-actions"><div id="community-qr"><QRCodeSVG value={shareURL} size={102} level="H" includeMargin bgColor="#ffffff" fgColor="#29213a" /></div><div><b>Ready to share</b><p>Download a print-ready card with the group link and QR.</p><button className="button button-outline button-small" onClick={downloadCard}>Download share card <ArrowDownRight size={14}/></button></div></div>
              <button className="share-open" onClick={() => onOpen(group)}>Preview public community page <ArrowUpRight size={15}/></button>
            </div>
            <div className="host-note"><ShieldCheck size={16}/><span>Group conversations and member names are visible only to people who join and the therapist host.</span></div>
          </div>
        </div>
      </div>}
    </div>}
  </>
}

function AuthModal({ email, setEmail, message, setMessage, onGoogle, onEmail, onClose }) {
  useEffect(() => { const key = e => { if (e.key === 'Escape') onClose() }; window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key) }, [onClose])
  return <div className="modal-scrim" onMouseDown={e => e.target === e.currentTarget && onClose()}><section className="modal-card auth-modal"><button className="modal-close" onClick={onClose} aria-label="Close"><X size={18}/></button><span className="brand-mark large"><Brain size={25}/></span><div className="eyebrow">Your account</div><h2>Join the conversation</h2><p>Explore stays open. Sign in only when you join a community or take part.</p>
    <button className="google-button" onClick={onGoogle}><span className="google-g">G</span> Continue with Google</button>
    <div className="divider"><span>or use your email</span></div>
    <form onSubmit={onEmail}><label>Email address<input className="clean-input" type="email" required value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com"/></label><button className="button button-primary full" type="submit">Email me a sign-in link <ArrowRight size={16}/></button></form>
    {message && <div className="auth-message">{message}</div>}<small className="privacy-note">A secure sign-in link keeps your password private.</small>
  </section></div>
}

function CreateModal({ onClose, onCreate }) {
  const [form, setForm] = useState({ name: '', topic: '', description: '', guidelines: '', memberLimit: 50 })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const submit = async event => { event.preventDefault(); setSaving(true); setError(''); try { await onCreate(form) } catch (e) { setError(e.message || 'Couldn’t create the community.') } finally { setSaving(false) } }
  return <div className="modal-scrim" onMouseDown={e => e.target === e.currentTarget && onClose()}><section className="modal-card create-modal"><button className="modal-close" onClick={onClose} aria-label="Close"><X size={18}/></button><div className="eyebrow">Build your circle</div><h2>New community</h2><p>A focused name and clear expectations help people know if this group is right for them.</p>
    <form onSubmit={submit} className="create-form"><label>Community name<input className="clean-input" required maxLength="70" value={form.name} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="e.g. Finding balance together"/></label>
      <label>Group focus<input className="clean-input" required maxLength="80" value={form.topic} onChange={e => setForm({ ...form, topic: e.target.value })} placeholder="e.g. Managing stress"/></label>
      <label>What is this space for?<textarea className="clean-input" required rows="3" value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Describe the support and resources members will find here."/></label>
      <label>Shared expectations<textarea className="clean-input" rows="3" value={form.guidelines} onChange={e => setForm({ ...form, guidelines: e.target.value })} placeholder="Optional guidelines for respectful discussion"/></label>
      <label>Member limit<input className="clean-input" type="number" min="2" max="500" value={form.memberLimit} onChange={e => setForm({ ...form, memberLimit: e.target.value })}/></label>
      {error && <p className="form-error">{error}</p>}<div className="modal-actions"><button type="button" className="button button-outline" onClick={onClose}>Cancel</button><button type="submit" className="button button-primary" disabled={saving}>{saving ? 'Creating…' : 'Create community'} <ArrowRight size={15}/></button></div>
    </form>
  </section></div>
}

createRoot(document.getElementById('root')).render(<React.StrictMode><App /></React.StrictMode>)

function xmlEscape(value) {
  return String(value).replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[character])
}
