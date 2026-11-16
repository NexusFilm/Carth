import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy, in plain language")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(CatharsiaStyle.ink)

                Text("Catharsia lets anyone read public therapist education without an account. You sign in only when you choose an action that saves or submits information.")
                    .font(.body)
                    .foregroundStyle(CatharsiaStyle.muted)

                policySection("What we store", text: "If you create an account, Supabase processes your name, chosen username, optional profile photo, email address, and account ID for Catharsia. Your name, username, and profile photo are public when they appear beside your comments. When signed in, likes, saved posts, comments, reports, and blocked-account preferences are associated with your account. If you request therapist publishing access, Catharsia stores your professional name, email, credentials, license number, license jurisdiction, and optional specialties for administrator review. Only you and authorized Catharsia administrators can read the license number; it is not included on your public profile. Authorized publishers can submit captions, photos, and short videos for public posts. Published posts and their media can be viewed without signing in.")
                policySection("What is public", text: "Therapist posts and comments are readable without signing in. Comments show your chosen display name, optional username, optional profile photo, and the text you submit. Comments may include personal health information if you choose to share it, so do not post diagnoses, treatment records, or information that should stay confidential.")
                policySection("Photos and videos", text: "An authorized publisher can use the in-app camera or choose media from Photos. Photos are resized and recompressed as JPEGs. Videos are converted to 720p MP4, limited to 60 seconds, and compressed before upload. A post can contain up to five media items; each item must be under 48 MB in the app, and Supabase rejects files larger than 50 MB. Published media is publicly viewable with its post, so avoid including private or identifying details.")
                policySection("How we use data", text: "Catharsia uses account and activity data to provide sign-in, publishing, comments, likes, saves, reporting, blocking, and account security. The app does not include advertising or cross-app tracking SDKs.")
                policySection("Hosting and retention", text: "Catharsia uses a dedicated tenant within the existing Supabase project. Account data and submitted content remain while your account is active. Delete Catharsia data in Profile removes your Catharsia profile, posts and their media, comments, likes, saves, reports you submitted, therapist access requests and license details, and blocked-account preferences. The request form does not collect identity documents. Your shared Nexus sign-in remains available to other apps that use this Supabase project. If other members reported a post or comment you published, the safety report may remain after that content is removed so administrators can keep a moderation record.")
                policySection("Health information", text: "Catharsia provides general education, not diagnosis, treatment, or emergency care. Please do not use comments to share personal health records or other confidential information. If you may be in immediate danger in the United States, call or text 988; contact local emergency services for immediate danger.")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Questions about privacy?")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.ink)
                    Link("support@nexusmobiletech.com", destination: URL(string: "mailto:support@nexusmobiletech.com")!)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CatharsiaStyle.violet)
                    Link(destination: URL(string: "https://nexusmobiletech.com/privacy/catharsia")!) {
                        Label("Read the full privacy policy", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CatharsiaStyle.violet)
                    }
                    .accessibilityHint("Opens Catharsia’s public privacy policy on nexusmobiletech.com")
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 620, alignment: .leading)
        }
        .background(CatharsiaStyle.canvas.ignoresSafeArea())
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(CatharsiaStyle.canvas, for: .navigationBar)
    }

    private func policySection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(CatharsiaStyle.ink)
            Text(text)
                .font(.subheadline)
                .lineSpacing(4)
                .foregroundStyle(CatharsiaStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
