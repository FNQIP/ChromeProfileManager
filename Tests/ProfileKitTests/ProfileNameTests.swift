import Testing
@testable import ProfileKit

@Suite("名称校验")
struct ProfileNameTests {

    @Test("接受普通名称")
    func acceptsOrdinaryNames() throws {
        #expect(try ProfileName.validated("我") == "我")
        #expect(try ProfileName.validated("我（副）") == "我（副）")
        #expect(try ProfileName.validated("Work Profile") == "Work Profile")
        #expect(try ProfileName.validated("工作-2026") == "工作-2026")
        #expect(try ProfileName.validated("a&b;c$d") == "a&b;c$d")
    }

    @Test("去除首尾空白")
    func trimsSurroundingWhitespace() throws {
        #expect(try ProfileName.validated("  老爸 \n") == "老爸")
    }

    @Test("拒绝空名称")
    func rejectsEmptyInput() {
        expectThrows(ProfileNameError.empty) { try ProfileName.validated("") }
    }

    @Test("拒绝纯空白名称")
    func rejectsWhitespaceOnly() {
        expectThrows(ProfileNameError.whitespaceOnly) { try ProfileName.validated("   \t\n ") }
    }

    @Test("拒绝路径分隔符")
    func rejectsPathSeparators() {
        expectThrows(ProfileNameError.containsPathSeparator) { try ProfileName.validated("a/b") }
        expectThrows(ProfileNameError.containsPathSeparator) { try ProfileName.validated("a:b") }
    }

    @Test("拒绝路径穿越")
    func rejectsPathTraversal() {
        for candidate in [".", "..", "../escape", "a..b"] {
            expectThrows(ProfileNameError.pathTraversal) { try ProfileName.validated(candidate) }
        }
    }

    @Test("拒绝隐藏名称")
    func rejectsHiddenNames() {
        expectThrows(ProfileNameError.hiddenName) { try ProfileName.validated(".hidden") }
    }

    @Test("拒绝控制字符")
    func rejectsControlCharacters() {
        expectThrows(ProfileNameError.containsControlCharacters) { try ProfileName.validated("line\nbreak") }
    }

    @Test("拒绝过长名称")
    func rejectsOverlongNames() {
        let long = String(repeating: "长", count: ProfileName.maximumLength + 1)
        expectThrows(ProfileNameError.tooLong(max: ProfileName.maximumLength)) {
            try ProfileName.validated(long)
        }
    }

    @Test("isValid 便捷方法")
    func isValidConvenience() {
        #expect(ProfileName.isValid("我"))
        #expect(!ProfileName.isValid("  "))
    }
}
