import { CosmosClient, SqlQuerySpec } from "@azure/cosmos";
import { app, HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";

const getEnvValue = (key: string): string => {
    const value = process.env[key]
    if (!value) {
        throw Error(`Env variable ${key} not set`)
    }
    return value
}

const getDbContainer = async (context: InvocationContext) => {
    const client = new CosmosClient({
        endpoint: getEnvValue("SIGHTINGS_DB_ENDPOINT"),
        key: getEnvValue("SIGHTINGS_DB_MASTER_KEY")
    })

    const dbResponse = await client.databases.createIfNotExists({
        id: getEnvValue("SIGHTINGS_DB_NAME")
    })
    const database = dbResponse.database
    context.log("Database response", database);

    const coResponse = await database.containers.createIfNotExists({
        id: getEnvValue("SIGHTINGS_DB_CONTAINER_NAME")
    })
    context.log("Database container response", coResponse);
    return coResponse.container
}

export async function helloWorld(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    context.log(`Http function processed request for url "${request.url}"`);

    const name = request.query.get('name') || await request.text() || 'world';

    return {
        body: JSON.stringify({
            message: `Hello ${name}`
        }),
    };
};

const createSightingId = () => crypto.randomUUID().toString()

export async function addSighting(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    context.log(`Http function processed request for url "${request.url}"`);
    try {
        const container = await getDbContainer(context)
        const inputBody = await request.json()
        const newRecord = {
            ...(inputBody as object),
            id: createSightingId()
        }
        container.items.create(newRecord)

        return {
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(newRecord)
        };
    } catch (err) {
        context.error("Caught error", err)
        return {
            status: 500,
            body: JSON.stringify({
                "message": "Caught error during execution"
            })
        }
    }
};

const getSightingById = async (request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> => {
    context.log(`Http function processed request for url "${request.url}"`);
    try {
        const sightingId = request.params.id;
        context.log(`Retrieving sighting with id ${sightingId}`)
        const container = await getDbContainer(context)

        const querySpec: SqlQuerySpec = {
            query: "SELECT * FROM c WHERE c.id = @sightingId",
            parameters: [
                { name: "@sightingId", value: sightingId }
            ]
        };
        const response = await container.items.query(querySpec).fetchAll();
        context.log("Got response from query", response)
        const result = response.resources.length > 0 ? response.resources[0] : null
        if (!result) {
            return {
                status: 404,
                headers: {
                    "Content-Type": "application/json"
                },
                body: JSON.stringify({
                    "error": `Record with id ${sightingId} was not found`
                })
            };
        }
        return {
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify(result)
        };
    } catch (err) {
        context.error("Caught error", err)
        return {
            status: 500,
            body: JSON.stringify({
                "message": "Caught error during execution"
            })
        }
    }
}

app.http('hello-world', {
    methods: ['GET'],
    authLevel: 'anonymous',
    handler: helloWorld
});

app.http('addSighting', {
    methods: ['POST'],
    authLevel: 'function',
    route: 'sighting',
    handler: addSighting
})

app.http('getSighting', {
    methods: ['GET'],
    authLevel: 'function',
    route: 'sighting/{id:guid?}',
    handler: getSightingById
});
