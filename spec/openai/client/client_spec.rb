RSpec.describe OpenAI::Client do
  context "with clients with different access tokens" do
    before do
      OpenAI.configure do |config|
        config.organization_id = "organization_id0"
        config.extra_headers = { "test" => "X-Default" }
      end
    end

    after do
      # Necessary otherwise the dummy organization_id bleeds into other specs
      # that actually hit the API and causes them to fail.
      OpenAI.configure do |config|
        config.organization_id = nil
        config.extra_headers = {}
      end
    end

    let!(:c0) { OpenAI::Client.new }
    let!(:c1) do
      OpenAI::Client.new(
        api_type: "azure",
        access_token: "access_token1",
        organization_id: "organization_id1",
        request_timeout: 60,
        uri_base: "https://oai.hconeai.com/",
        extra_headers: { "test" => "X-Test" }
      )
    end
    let!(:c2) do
      OpenAI::Client.new(
        access_token: "access_token2",
        request_timeout: 1,
        uri_base: "https://example.com/"
      )
    end

    it "does not confuse the clients" do
      expect(c0.azure?).to eq(false)
      expect(c0.access_token).to eq(ENV.fetch("OPENAI_ACCESS_TOKEN", "dummy-token"))
      expect(c0.organization_id).to eq("organization_id0")
      expect(c0.request_timeout).to eq(OpenAI::Configuration::DEFAULT_REQUEST_TIMEOUT)
      expect(c0.uri_base).to eq(OpenAI::Configuration::DEFAULT_URI_BASE)
      expect(c0.send(:headers).values).to include("Bearer #{c0.access_token}")
      expect(c0.send(:headers).values).to include(c0.organization_id)
      expect(c0.send(:conn).options.timeout).to eq(OpenAI::Configuration::DEFAULT_REQUEST_TIMEOUT)
      expect(c0.send(:uri, path: "")).to include(OpenAI::Configuration::DEFAULT_URI_BASE)
      expect(c0.send(:headers).values).to include("X-Default")
      expect(c0.send(:headers).values).not_to include("X-Test")

      expect(c1.azure?).to eq(true)
      expect(c1.access_token).to eq("access_token1")
      expect(c1.organization_id).to eq("organization_id1")
      expect(c1.request_timeout).to eq(60)
      expect(c1.uri_base).to eq("https://oai.hconeai.com/")
      expect(c1.send(:headers).values).to include(c1.access_token)
      expect(c1.send(:conn).options.timeout).to eq(60)
      expect(c1.send(:uri, path: "")).to include("https://oai.hconeai.com/")
      expect(c1.send(:headers).values).not_to include("X-Default")
      expect(c1.send(:headers).values).to include("X-Test")

      expect(c2.azure?).to eq(false)
      expect(c2.access_token).to eq("access_token2")
      expect(c2.organization_id).to eq("organization_id0") # Fall back to default.
      expect(c2.request_timeout).to eq(1)
      expect(c2.uri_base).to eq("https://example.com/")
      expect(c2.send(:headers).values).to include("Bearer #{c2.access_token}")
      expect(c2.send(:headers).values).to include(c2.organization_id)
      expect(c2.send(:conn).options.timeout).to eq(1)
      expect(c2.send(:uri, path: "")).to include("https://example.com/")
      expect(c2.send(:headers).values).to include("X-Default")
      expect(c2.send(:headers).values).not_to include("X-Test")
    end

    context "hitting other classes" do
      after do
        c0.files.list
        c1.files.list
        c2.files.list

        c0.finetunes.list
        c1.finetunes.list
        c2.finetunes.list

        c0.images.generate
        c1.images.generate
        c2.images.generate

        c0.models.list
        c1.models.list
        c2.models.list
      end

      it "does not confuse the clients" do
        expect(c0).to receive(:get).with(path: "/files", parameters: {}).once
        expect(c1).to receive(:get).with(path: "/files", parameters: {}).once
        expect(c2).to receive(:get).with(path: "/files", parameters: {}).once

        expect(c0).to receive(:get).with(path: "/fine_tuning/jobs").once
        expect(c1).to receive(:get).with(path: "/fine_tuning/jobs").once
        expect(c2).to receive(:get).with(path: "/fine_tuning/jobs").once

        expect(c0).to receive(:json_post).with(path: "/images/generations", parameters: {}).once
        expect(c1).to receive(:json_post).with(path: "/images/generations", parameters: {}).once
        expect(c2).to receive(:json_post).with(path: "/images/generations", parameters: {}).once

        expect(c0).to receive(:get).with(path: "/models").once
        expect(c1).to receive(:get).with(path: "/models").once
        expect(c2).to receive(:get).with(path: "/models").once
      end
    end
  end

  context "when using admin endpoints" do
    let(:admin_token) { "admin-token" }

    context "with admin token configured" do
      let(:client) do
        OpenAI::Client.new(admin_token: admin_token)
      end

      it "creates a new client instance with admin token as access token" do
        admin_client = client.admin
        expect(admin_client).not_to eq(client)
        expect(admin_client.access_token).to eq(admin_token)
        expect(client.access_token).not_to eq(admin_token) # Original unchanged
      end
    end

    context "when using both beta and admin" do
      let(:client) do
        OpenAI::Client.new(admin_token: admin_token)
      end

      it "allows chaining beta and admin" do
        admin_beta_client = client.beta(assistants: "v2").admin
        expect(admin_beta_client.access_token).to eq(admin_token)
        expect(admin_beta_client.send(:headers)["OpenAI-Beta"]).to eq "assistants=v2"
      end

      it "allows chaining admin and beta" do
        admin_beta_client = client.admin.beta(assistants: "v2")
        expect(admin_beta_client.access_token).to eq(admin_token)
        expect(admin_beta_client.send(:headers)["OpenAI-Beta"]).to eq "assistants=v2"
      end
    end
  end

  context "when using beta APIs" do
    let(:client) { OpenAI::Client.new.beta(assistants: "v2") }

    it "sends the appropriate header value" do
      expect(client.send(:headers)["OpenAI-Beta"]).to eq "assistants=v2"
    end
  end

  context "with a block" do
    let(:client) do
      OpenAI::Client.new do |client|
        client.response :logger, Logger.new($stdout), bodies: true
      end
    end

    it "sets the logger" do
      connection = Faraday.new
      client.faraday_middleware.call(connection)
      expect(connection.builder.handlers).to include Faraday::Response::Logger
    end
  end

  context "when calling inspect" do
    let(:api_key) { "sk-123456789" }
    let(:organization_id) { "org-123456789" }
    let(:extra_headers) { { "Other-Auth": "key-123456789" } }
    let(:uri_base) { "https://example.com/" }
    let(:request_timeout) { 500 }
    let(:client) do
      OpenAI::Client.new(
        uri_base: uri_base,
        request_timeout: request_timeout,
        access_token: api_key,
        organization_id: organization_id,
        extra_headers: extra_headers
      )
    end

    it "does not expose sensitive information" do
      expect(client.inspect).not_to include(api_key)
      expect(client.inspect).not_to include(organization_id)
      expect(client.inspect).not_to include(extra_headers[:"Other-Auth"])
    end

    it "does expose non-sensitive information" do
      expect(client.inspect).to include(uri_base.inspect)
      expect(client.inspect).to include(request_timeout.inspect)
      expect(client.inspect).to include(client.object_id.to_s)
      expect(client.inspect).to include(client.class.to_s)
    end
  end
end
