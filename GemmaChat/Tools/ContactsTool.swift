import Foundation
import Contacts

struct SearchContactsTool: Tool {
    let name = "search_contacts"
    let description = "Search contacts by name and return phone numbers, emails"
    let parameters = [ToolParameter("query", "Name to search for")]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let query = arguments["query"], !query.isEmpty else {
            return .fail("query parameter is required")
        }

        let store = CNContactStore()

        do {
            let authorized = try await store.requestAccess(for: .contacts)
            guard authorized else {
                return .fail("연락처 접근 권한이 거부되었습니다. 설정에서 허용해주세요.")
            }
        } catch {
            return .fail("연락처 권한 요청 실패: \(error.localizedDescription)")
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor
        ]

        let predicate = CNContact.predicateForContacts(matchingName: query)

        do {
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)

            if contacts.isEmpty {
                return .ok("'\(query)'에 해당하는 연락처를 찾을 수 없습니다.")
            }

            var results: [String] = []
            for contact in contacts.prefix(5) {
                let fullName = [contact.familyName, contact.givenName]
                    .filter { !$0.isEmpty }.joined(separator: " ")
                var lines = ["**\(fullName)**"]

                for phone in contact.phoneNumbers {
                    let number = phone.value.stringValue
                    let cleaned = number.replacingOccurrences(of: " ", with: "")
                    lines.append("전화: [\(number)](tel:\(cleaned))")
                }

                for email in contact.emailAddresses {
                    let addr = email.value as String
                    lines.append("메일: [\(addr)](mailto:\(addr))")
                }

                if !contact.organizationName.isEmpty {
                    lines.append("회사: \(contact.organizationName)")
                }

                let info = lines.joined(separator: "\n")

                results.append(info)
            }

            let countInfo = contacts.count > 5 ? " (총 \(contacts.count)건 중 5건 표시)" : ""
            return .ok(results.joined(separator: "\n") + countInfo)
        } catch {
            return .fail("연락처 검색 실패: \(error.localizedDescription)")
        }
    }
}

struct AddContactTool: Tool {
    let name = "add_contact"
    let description = "Add a new contact to the address book"
    let parameters = [
        ToolParameter("name", "Contact name (family name + given name)"),
        ToolParameter("phone", "Phone number", required: false),
        ToolParameter("email", "Email address", required: false)
    ]

    func execute(arguments: [String: String]) async -> ToolResult {
        guard let name = arguments["name"], !name.isEmpty else {
            return .fail("name parameter is required")
        }

        let store = CNContactStore()

        do {
            let authorized = try await store.requestAccess(for: .contacts)
            guard authorized else {
                return .fail("연락처 접근 권한이 거부되었습니다. 설정에서 허용해주세요.")
            }
        } catch {
            return .fail("연락처 권한 요청 실패: \(error.localizedDescription)")
        }

        let newContact = CNMutableContact()

        let nameParts = name.components(separatedBy: " ")
        if nameParts.count >= 2 {
            newContact.familyName = nameParts[0]
            newContact.givenName = nameParts[1...].joined(separator: " ")
        } else {
            newContact.givenName = name
        }

        if let phone = arguments["phone"], !phone.isEmpty {
            newContact.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile,
                               value: CNPhoneNumber(stringValue: phone))
            ]
        }

        if let email = arguments["email"], !email.isEmpty {
            newContact.emailAddresses = [
                CNLabeledValue(label: CNLabelHome, value: email as NSString)
            ]
        }

        let saveRequest = CNSaveRequest()
        saveRequest.add(newContact, toContainerWithIdentifier: nil)

        do {
            try store.execute(saveRequest)
            var summary = "'\(name)' 연락처를 추가했습니다."
            if let phone = arguments["phone"] { summary += " 전화: \(phone)" }
            if let email = arguments["email"] { summary += " 이메일: \(email)" }
            return .ok(summary)
        } catch {
            return .fail("연락처 추가 실패: \(error.localizedDescription)")
        }
    }
}
