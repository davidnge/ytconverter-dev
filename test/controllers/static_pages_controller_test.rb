require "test_helper"

class StaticPagesControllerTest < ActionDispatch::IntegrationTest
  test "should get contact" do
    get static_pages_contact_url
    assert_response :success
  end

  test "should get copyright_claims" do
    get static_pages_copyright_claims_url
    assert_response :success
  end

  test "should get privacy_policy" do
    get static_pages_privacy_policy_url
    assert_response :success
  end

  test "should get terms_of_use" do
    get static_pages_terms_of_use_url
    assert_response :success
  end
end
