import SwiftUI

#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var cookieSaved = KeychainStore.loadCookie() != nil
    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var toast: String?

    private let loginURL = URL(string: "https://accounts.douban.com/passport/login")!

    var body: some View {
        SheetScaffold {
            VStack(spacing: 0) {
                SheetGrabber()
                SheetHeader(
                    title: L10n.Records.loginDouban,
                    leftTitle: L10n.Common.close,
                    rightTitle: L10n.Common.done,
                    onLeft: { dismiss() },
                    onRight: { completeLogin() }
                )
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.Records.inAppLogin)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                    Spacer()
                    TagView(text: L10n.Records.recommendation, style: .gold)
                }
                .padding(.horizontal, 18)

                DoubanLoginWebView(url: loginURL)
                    .frame(height: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                InfoGroup {
                    FieldRow(label: L10n.Records.loginSession) {
                        HStack(spacing: 5) {
                            Image(systemName: cookieSaved ? "checkmark.shield.fill" : "lock")
                                .foregroundStyle(cookieSaved ? Theme.read : Theme.text4)
                            Text(cookieSaved ? L10n.Records.keychainSaved : L10n.Records.localKeychain)
                        }
                    }
                    FieldRow(label: L10n.Records.forSync, showDivider: false) {
                        Text(L10n.Records.privateDoulist)
                            .foregroundStyle(Theme.text3)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Text(L10n.Records.inAppLoginHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text3)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    Button {
                        openURL(loginURL)
                    } label: {
                        Label(L10n.Records.openInSafari, systemImage: "safari")
                    }
                    .buttonStyle(SoftButtonStyle())

                    Button {
                        showPaste = true
                    } label: {
                        Label(L10n.Records.pasteCookie, systemImage: "doc.on.doc")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Text(L10n.Records.loginFallbackHint)
                    .font(.appCaption)
                    .foregroundStyle(Theme.text4)
                    .lineSpacing(3)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }
        }
        .toast(message: $toast)
        .alert(Text(L10n.Records.pasteCookie), isPresented: $showPaste) {
            TextField(L10n.Records.cookieExample, text: $pasteText)
            Button(L10n.Common.save) {
                let value = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { return }
                KeychainStore.saveCookie(value)
                cookieSaved = true
                toast = L10n.Records.cookieSavedToKeychain
            }
            Button(L10n.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Records.copyCookieHint)
        }
    }

    private func completeLogin() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let doubanCookies = cookies.filter { $0.domain.contains("douban.com") }
            let header = doubanCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            DispatchQueue.main.async {
                if header.isEmpty {
                    toast = L10n.Records.cookieNotDetected
                } else {
                    KeychainStore.saveCookie(header)
                    cookieSaved = true
                    toast = L10n.Records.loginSessionSaved
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DoubanLoginWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

#else

struct LoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.Records.inAppLoginIPhoneHint)
                .font(.appBody)
                .foregroundStyle(Theme.text2)
            Button(L10n.Records.openDoubanInSafari) {
                openURL(URL(string: "https://accounts.douban.com/passport/login")!)
            }
            .buttonStyle(GoldButtonStyle())
            Button(L10n.Common.close) { dismiss() }
                .foregroundStyle(Theme.gold)
        }
        .padding(24)
        .background(Theme.sheet)
    }
}

#endif
